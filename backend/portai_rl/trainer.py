"""Real Stable-Baselines3 training and held-out test evaluation."""

from __future__ import annotations

import csv
import json
import math
import os
import time
import traceback
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

import numpy as np

from .contracts import ALGORITHM_IDS, PortDataset, atomic_write_json, load_dataset, sha256_file
from .environment import LosPidController, OBSERVATION_SIZE, PortTrafficEnv


@dataclass(frozen=True)
class TrainRequest:
    algorithm: str
    manifest_path: Path
    output_dir: Path
    progress_path: Path
    checkpoint_path: Path
    total_timesteps: int = 20_000
    max_episode_steps: int = 96
    seed: int = 42
    learning_rate: float = 3e-4
    gamma: float = 0.99
    batch_size: int = 128
    replay_buffer_size: int = 50_000
    rollout_horizon: int = 256
    entropy_coef: float = 0.01


@dataclass(frozen=True)
class EvaluateRequest:
    algorithm: str
    manifest_path: Path
    output_dir: Path
    progress_path: Path
    checkpoint_path: Path
    trajectory_path: Path
    episodes: int = 1
    max_episode_steps: int = 96
    seed: int = 42


def _sb3_imports() -> dict[str, Any]:
    try:
        from stable_baselines3 import DQN, PPO, SAC, TD3
        from stable_baselines3.common.callbacks import BaseCallback
        from stable_baselines3.common.monitor import Monitor
        from stable_baselines3.common.vec_env import DummyVecEnv
    except ImportError as exc:
        raise RuntimeError(
            "RL dependencies are missing. Install backend/requirements.txt in a Python 3.12-3.14 environment."
        ) from exc
    return {
        "ppo": PPO,
        "sac": SAC,
        "td3": TD3,
        "dqn": DQN,
        "BaseCallback": BaseCallback,
        "Monitor": Monitor,
        "DummyVecEnv": DummyVecEnv,
    }


def _safe_batch_size(requested: int, rollout_size: int) -> int:
    maximum = max(2, min(int(requested), int(rollout_size)))
    candidates = [size for size in range(2, maximum + 1) if rollout_size % size == 0]
    return max(candidates) if candidates else 2


def _make_training_env(dataset: PortDataset, request: TrainRequest, discrete: bool) -> Callable[[], Any]:
    imports = _sb3_imports()
    Monitor = imports["Monitor"]

    def create() -> Any:
        environment = PortTrafficEnv(
            dataset,
            split="train",
            discrete_actions=discrete,
            max_steps=request.max_episode_steps,
            seed=request.seed,
            render_mode=None,
            random_start=True,
        )
        return Monitor(environment)

    return create


def _build_model(algorithm: str, env: Any, request: TrainRequest, imports: Mapping[str, Any]) -> Any:
    common = {
        "policy": "MlpPolicy",
        "env": env,
        "learning_rate": request.learning_rate,
        "gamma": request.gamma,
        "seed": request.seed,
        "verbose": 0,
        "device": "auto",
        "tensorboard_log": None,
        "policy_kwargs": {"net_arch": [128, 128]},
    }
    if algorithm == "ppo":
        n_steps = max(8, min(request.rollout_horizon, request.total_timesteps))
        return imports["ppo"](
            **common,
            n_steps=n_steps,
            batch_size=_safe_batch_size(request.batch_size, n_steps),
            n_epochs=10,
            gae_lambda=0.95,
            ent_coef=request.entropy_coef,
        )
    learning_starts = min(1_000, max(1, request.total_timesteps // 5))
    buffer_size = max(1_000, request.replay_buffer_size)
    batch_size = max(16, min(request.batch_size, 512))
    if algorithm == "sac":
        return imports["sac"](
            **common,
            buffer_size=buffer_size,
            learning_starts=learning_starts,
            batch_size=batch_size,
            train_freq=1,
            gradient_steps=1,
        )
    if algorithm == "td3":
        from stable_baselines3.common.noise import NormalActionNoise

        return imports["td3"](
            **common,
            buffer_size=buffer_size,
            learning_starts=learning_starts,
            batch_size=batch_size,
            train_freq=1,
            gradient_steps=1,
            action_noise=NormalActionNoise(mean=np.zeros(2), sigma=np.full(2, 0.1)),
        )
    return imports["dqn"](
        **common,
        buffer_size=buffer_size,
        learning_starts=learning_starts,
        batch_size=batch_size,
        train_freq=4,
        gradient_steps=1,
        target_update_interval=max(100, request.total_timesteps // 20),
        exploration_initial_eps=0.9,
        exploration_final_eps=0.05,
        exploration_fraction=0.65,
    )


def _progress_callback_class(imports: Mapping[str, Any]) -> type:
    BaseCallback = imports["BaseCallback"]

    class JsonProgressCallback(BaseCallback):
        def __init__(self, request: TrainRequest, dataset: PortDataset) -> None:
            super().__init__(verbose=0)
            self.request = request
            self.dataset = dataset
            self.episodes: list[dict[str, Any]] = []
            self.history: list[dict[str, Any]] = []
            self.started = time.monotonic()
            self.last_write = -1

        def _on_step(self) -> bool:
            for info in self.locals.get("infos", []):
                episode = info.get("episode") if isinstance(info, Mapping) else None
                if isinstance(episode, Mapping):
                    self.episodes.append(
                        {
                            "episode": len(self.episodes) + 1,
                            "step": int(self.num_timesteps),
                            "reward": float(episode.get("r", 0.0)),
                            "length": int(episode.get("l", 0)),
                            "throughput": float(info.get("throughput", 0.0)),
                            "congestion": float(info.get("congestion", 0.0)),
                            "conflict_risk": float(info.get("conflict_risk", 0.0)),
                        }
                    )
            interval = max(16, min(200, self.request.total_timesteps // 100 or 16))
            if self.num_timesteps - self.last_write < interval and self.num_timesteps < self.request.total_timesteps:
                return True
            self.last_write = self.num_timesteps
            recent = self.episodes[-20:]
            reward = float(np.mean([item["reward"] for item in recent])) if recent else 0.0
            elapsed = time.monotonic() - self.started
            point = {
                "step": int(self.num_timesteps),
                "reward": reward,
                "episodes": len(self.episodes),
                "elapsed_seconds": elapsed,
            }
            self.history.append(point)
            atomic_write_json(
                self.request.progress_path,
                {
                    "status": "RUNNING",
                    "operation": "train",
                    "stage": "headless_policy_update",
                    "algorithm": self.request.algorithm,
                    "step": int(self.num_timesteps),
                    "total_steps": self.request.total_timesteps,
                    "progress": min(100.0 * self.num_timesteps / max(self.request.total_timesteps, 1), 100.0),
                    "reward": reward,
                    "episodes_completed": len(self.episodes),
                    "step_rate_per_second": self.num_timesteps / max(elapsed, 1e-6),
                    "render": False,
                    "render_mode": None,
                    "dataset_split": "train",
                    "dataset_sha256": self.dataset.dataset_sha256,
                    "history": self.history[-100:],
                    "logs": [
                        f"train split only · {self.dataset.train.rows} rows",
                        "render_mode=None · graphical rendering disabled",
                        f"real trainer step {self.num_timesteps}/{self.request.total_timesteps}",
                    ],
                },
            )
            return True

    return JsonProgressCallback


def _write_csv(path: Path, rows: Sequence[Mapping[str, Any]]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _run_pid_episode(
    dataset: PortDataset,
    split: str,
    controller: LosPidController,
    *,
    max_steps: int,
    seed: int,
    render_mode: str | None,
) -> tuple[dict[str, Any], PortTrafficEnv]:
    env = PortTrafficEnv(
        dataset,
        split=split,
        discrete_actions=False,
        max_steps=max_steps,
        seed=seed,
        render_mode=render_mode,
        random_start=False,
    )
    observation, _ = env.reset(options={"start_index": 0})
    del observation
    controller.reset()
    terminated = truncated = False
    info: dict[str, Any] = {}
    while not (terminated or truncated):
        action = controller.predict(env)
        _, _, terminated, truncated, info = env.step(action)
    return _episode_result(env, info), env


def _tune_pid(dataset: PortDataset, request: TrainRequest) -> tuple[dict[str, float], list[dict[str, Any]]]:
    gain_grid = [
        (kp, ki, kd)
        for kp in (0.6, 0.9, 1.2, 1.5, 1.8)
        for ki in (0.00, 0.02)
        for kd in (0.05, 0.18, 0.30)
    ]
    rng = np.random.default_rng(request.seed)
    candidate_count = min(max(request.total_timesteps, 1), len(gain_grid))
    candidates = [gain_grid[int(index)] for index in rng.permutation(len(gain_grid))[:candidate_count]]
    trials: list[dict[str, Any]] = []
    for index, (kp, ki, kd) in enumerate(candidates):
        controller = LosPidController(kp, ki, kd)
        result, env = _run_pid_episode(
            dataset,
            "train",
            controller,
            max_steps=request.max_episode_steps,
            seed=request.seed + index,
            render_mode=None,
        )
        if env.frames or env.render_calls:
            raise RuntimeError("training render boundary was violated by LOS-PID")
        trials.append({"kp": kp, "ki": ki, "kd": kd, **result})
        atomic_write_json(
            request.progress_path,
            {
                "status": "RUNNING",
                "operation": "train",
                "stage": "headless_pid_calibration",
                "algorithm": "los_pid",
                "step": index + 1,
                "total_steps": len(candidates),
                "progress": 100.0 * (index + 1) / len(candidates),
                "reward": result["reward"],
                "render": False,
                "render_mode": None,
                "dataset_split": "train",
                "dataset_sha256": dataset.dataset_sha256,
                "history": trials,
                "logs": [
                    "LOS-PID gains calibrated on training split only",
                    f"trial {index + 1}/{len(candidates)} · Kp={kp} Ki={ki} Kd={kd}",
                ],
            },
        )
    best = max(trials, key=lambda item: float(item["reward"]))
    return {"kp": float(best["kp"]), "ki": float(best["ki"]), "kd": float(best["kd"])}, trials


def train(request: TrainRequest) -> dict[str, Any]:
    if request.algorithm not in ALGORITHM_IDS:
        raise ValueError(f"unsupported algorithm: {request.algorithm}")
    if request.total_timesteps < 1:
        raise ValueError("total_timesteps must be positive")
    request.output_dir.mkdir(parents=True, exist_ok=True)
    dataset = load_dataset(request.manifest_path)
    atomic_write_json(
        request.progress_path,
        {
            "status": "STARTING",
            "operation": "train",
            "stage": "load_train_split",
            "algorithm": request.algorithm,
            "step": 0,
            "total_steps": request.total_timesteps,
            "progress": 0.0,
            "render": False,
            "render_mode": None,
            "dataset_split": "train",
            "dataset_sha256": dataset.dataset_sha256,
        },
    )
    started = time.monotonic()
    checkpoint: dict[str, Any]
    history: list[dict[str, Any]] = []
    episodes: list[dict[str, Any]] = []
    model_path: Path | None = None
    actual_timesteps = 0
    if request.algorithm == "los_pid":
        gains, history = _tune_pid(dataset, request)
        checkpoint = {
            "format": "portai_policy_checkpoint_v1",
            "algorithm": "los_pid",
            "library": "control_theory",
            "controller": {"type": "los_pid", **gains},
            "trained": False,
            "calibrated": True,
            "calibration_trials": len(history),
        }
    else:
        imports = _sb3_imports()
        vector_env = imports["DummyVecEnv"](
            [_make_training_env(dataset, request, request.algorithm == "dqn")]
        )
        model = _build_model(request.algorithm, vector_env, request, imports)
        callback = _progress_callback_class(imports)(request, dataset)
        model.learn(
            total_timesteps=request.total_timesteps,
            callback=callback,
            progress_bar=False,
        )
        actual_timesteps = int(model.num_timesteps)
        model_base = request.output_dir / f"{request.algorithm}_policy"
        model.save(model_base)
        model_path = model_base.with_suffix(".zip")
        history = callback.history
        episodes = callback.episodes
        vector_env.close()
        checkpoint = {
            "format": "portai_policy_checkpoint_v1",
            "algorithm": request.algorithm,
            "library": "stable-baselines3",
            "model_path": os.fspath(model_path),
            "model_sha256": sha256_file(model_path),
            "trained": True,
            "actual_timesteps": actual_timesteps,
            "action_space": "discrete_9" if request.algorithm == "dqn" else "continuous_box_2",
            "observation_size": OBSERVATION_SIZE,
        }
    training_history_path = request.output_dir / "training_history.json"
    atomic_write_json(
        training_history_path,
        {
            "format": "portai_training_history_v1",
            "algorithm": request.algorithm,
            "dataset_split": "train",
            "dataset_sha256": dataset.dataset_sha256,
            "render": False,
            "points": history,
        },
    )
    checkpoint.update(
        {
            "dataset_split_used": "train",
            "dataset_sha256": dataset.dataset_sha256,
            "experiment_sha256": dataset.experiment_sha256,
            "manifest_path": os.fspath(dataset.manifest_path),
            "seed": request.seed,
            "training_history_path": os.fspath(training_history_path),
            "training_history_sha256": sha256_file(training_history_path),
            "hyperparameters": {
                "total_timesteps": request.total_timesteps,
                "learning_rate": request.learning_rate,
                "gamma": request.gamma,
                "batch_size": request.batch_size,
                "replay_buffer_size": request.replay_buffer_size,
                "rollout_horizon": request.rollout_horizon,
                "entropy_coef": request.entropy_coef,
            },
        }
    )
    atomic_write_json(request.checkpoint_path, checkpoint)
    _write_csv(request.output_dir / f"{request.algorithm}_train_episodes.csv", episodes)
    _write_csv(request.output_dir / f"{request.algorithm}_train_history.csv", history)
    recent = episodes[-20:]
    reward = float(np.mean([item["reward"] for item in recent])) if recent else (
        float(history[-1].get("reward", 0.0)) if history else 0.0
    )
    result = {
        "status": "TRAINED",
        "ok": True,
        "operation": "train",
        "stage": "checkpoint_ready_test_pending",
        "algorithm": request.algorithm,
        "step": actual_timesteps if request.algorithm != "los_pid" else len(history),
        "total_steps": request.total_timesteps if request.algorithm != "los_pid" else len(history),
        "progress": 100.0,
        "reward": reward,
        "elapsed_seconds": time.monotonic() - started,
        "checkpoint_json": os.fspath(request.checkpoint_path),
        "model_path": os.fspath(model_path) if model_path else "",
        "render": False,
        "render_mode": None,
        "dataset_split": "train",
        "dataset_sha256": dataset.dataset_sha256,
        "experiment_sha256": dataset.experiment_sha256,
        "history": history[-100:],
        "logs": [
            "training complete · train split only",
            "no rendering occurred during training",
            "checkpoint written · starting held-out test evaluation",
        ],
    }
    atomic_write_json(request.progress_path, result)
    return result


def _resolve_run_artifact(raw_path: Any, output_dir: Path, *, label: str) -> Path:
    root = output_dir.resolve()
    candidate = Path(str(raw_path)).expanduser().resolve()
    if not candidate.is_relative_to(root):
        raise ValueError(f"{label} escapes the training artifact directory")
    return candidate


def _load_policy(checkpoint: Mapping[str, Any], output_dir: Path) -> Any:
    algorithm = str(checkpoint["algorithm"])
    if algorithm == "los_pid":
        value = checkpoint.get("controller", {})
        return LosPidController(value["kp"], value["ki"], value["kd"])
    imports = _sb3_imports()
    model_path = _resolve_run_artifact(
        checkpoint.get("model_path", ""), output_dir, label="model path"
    )
    if not model_path.exists():
        raise FileNotFoundError(f"trained model not found: {model_path}")
    if sha256_file(model_path) != checkpoint.get("model_sha256"):
        raise ValueError("model SHA-256 mismatch")
    return imports[algorithm].load(model_path, device="auto")


def _episode_result(env: PortTrafficEnv, info: Mapping[str, Any]) -> dict[str, Any]:
    frames = env.frames
    mean = lambda key: float(np.mean([frame[key] for frame in frames])) if frames else float(info.get(key, 0.0))
    return {
        "reward": float(env.total_reward),
        "steps": int(env.steps),
        "mean_throughput": mean("throughput"),
        "mean_congestion": mean("congestion"),
        "mean_conflict_risk": mean("conflict_risk"),
        "mean_safety_margin": mean("safety_margin"),
        "window_start": env.data.timestamps[env.start_index].isoformat(),
        "window_end": env.data.timestamps[env.index].isoformat(),
    }


def evaluate(request: EvaluateRequest) -> dict[str, Any]:
    checkpoint = json.loads(request.checkpoint_path.read_text(encoding="utf-8"))
    algorithm = str(checkpoint.get("algorithm"))
    if algorithm != request.algorithm:
        raise ValueError("checkpoint algorithm does not match evaluation request")
    dataset = load_dataset(request.manifest_path)
    if checkpoint.get("dataset_sha256") != dataset.dataset_sha256:
        raise ValueError("dataset changed after training; retrain before evaluation")
    if checkpoint.get("experiment_sha256") != dataset.experiment_sha256:
        raise ValueError("environment/reward contract changed after training; retrain first")
    completed_training_steps = int(
        checkpoint.get("actual_timesteps")
        or checkpoint.get("calibration_trials")
        or checkpoint.get("hyperparameters", {}).get("total_timesteps", 0)
    )
    training_history_path = _resolve_run_artifact(
        checkpoint.get("training_history_path", ""),
        request.output_dir,
        label="training history path",
    )
    if not training_history_path.exists():
        raise FileNotFoundError("training history artifact is missing")
    if sha256_file(training_history_path) != checkpoint.get("training_history_sha256"):
        raise ValueError("training history SHA-256 mismatch")
    training_history_payload = json.loads(training_history_path.read_text(encoding="utf-8"))
    if training_history_payload.get("dataset_split") != "train":
        raise ValueError("training history split contract is invalid")
    training_history = list(training_history_payload.get("points", []))[-100:]
    policy = _load_policy(checkpoint, request.output_dir)
    atomic_write_json(
        request.progress_path,
        {
            "status": "EVALUATING",
            "operation": "evaluate",
            "stage": "held_out_test_rollout",
            "algorithm": algorithm,
            "progress": 0.0,
            "step": completed_training_steps,
            "total_steps": completed_training_steps,
            "render": True,
            "render_mode": "recorded_test_trajectory",
            "dataset_split": "test",
            "dataset_sha256": dataset.dataset_sha256,
            "history": training_history,
            "logs": [
                "training process exited",
                "loading held-out test split",
                "recording evaluation trajectory for client rendering",
            ],
        },
    )
    started = time.monotonic()
    results: list[dict[str, Any]] = []
    selected_frames: list[dict[str, Any]] = []
    episode_count = max(1, min(int(request.episodes), 5))
    for episode in range(episode_count):
        env = PortTrafficEnv(
            dataset,
            split="test",
            discrete_actions=algorithm == "dqn",
            max_steps=request.max_episode_steps,
            seed=request.seed + episode,
            render_mode="trajectory",
            random_start=False,
        )
        observation, _ = env.reset(options={"start_index": 0})
        if algorithm == "los_pid":
            policy.reset()
        terminated = truncated = False
        info: dict[str, Any] = {}
        while not (terminated or truncated):
            if algorithm == "los_pid":
                action = policy.predict(env)
            else:
                action, _ = policy.predict(observation, deterministic=True)
            observation, _, terminated, truncated, info = env.step(action)
        frames = env.render()
        if env.render_calls != 1 or not frames:
            raise RuntimeError("evaluation trajectory renderer did not produce frames")
        result = _episode_result(env, info)
        results.append({"episode": episode + 1, **result})
        if not selected_frames:
            selected_frames = frames
        atomic_write_json(
            request.progress_path,
            {
                "status": "EVALUATING",
                "operation": "evaluate",
                "stage": "held_out_test_rollout",
                "algorithm": algorithm,
                "completed_episodes": episode + 1,
                "total_episodes": episode_count,
                "progress": 100.0 * (episode + 1) / episode_count,
                "step": completed_training_steps,
                "total_steps": completed_training_steps,
                "reward": result["reward"],
                "render": True,
                "render_mode": "recorded_test_trajectory",
                "dataset_split": "test",
                "dataset_sha256": dataset.dataset_sha256,
                "history": training_history,
            },
        )
    aggregate = {
        "episodes": len(results),
        "mean_reward": float(np.mean([item["reward"] for item in results])),
        "mean_throughput": float(np.mean([item["mean_throughput"] for item in results])),
        "mean_congestion": float(np.mean([item["mean_congestion"] for item in results])),
        "mean_conflict_risk": float(np.mean([item["mean_conflict_risk"] for item in results])),
        "mean_safety_margin": float(np.mean([item["mean_safety_margin"] for item in results])),
    }
    trajectory = {
        "format": "portai_policy_test_rollout_v1",
        "source": "deterministic_policy_on_held_out_test_split",
        "algorithm": algorithm,
        "dataset_split": "test",
        "dataset_sha256": dataset.dataset_sha256,
        "experiment_sha256": dataset.experiment_sha256,
        "playback_mode": "recorded_test_rollout",
        "rendered_after_training": True,
        "frames": selected_frames,
        "episode_metrics": results,
        "aggregate_metrics": aggregate,
    }
    atomic_write_json(request.trajectory_path, trajectory)
    _write_csv(request.output_dir / f"{algorithm}_test_episodes.csv", results)
    result = {
        "status": "COMPLETED",
        "ok": True,
        "operation": "evaluate",
        "stage": "test_trajectory_ready",
        "algorithm": algorithm,
        "progress": 100.0,
        "step": completed_training_steps,
        "total_steps": completed_training_steps,
        "reward": aggregate["mean_reward"],
        "elapsed_seconds": time.monotonic() - started,
        "trajectory_json": os.fspath(request.trajectory_path),
        "evaluation_metrics": results[0],
        "aggregate_metrics": aggregate,
        "render": True,
        "render_mode": "recorded_test_trajectory",
        "render_ready": True,
        "dataset_split": "test",
        "dataset_sha256": dataset.dataset_sha256,
        "experiment_sha256": dataset.experiment_sha256,
        "history": training_history,
        "logs": [
            "held-out test evaluation complete",
            f"trajectory frames written: {len(selected_frames)}",
            "mobile client may now render the recorded test rollout",
        ],
    }
    atomic_write_json(request.progress_path, result)
    return result


def guarded_run(progress_path: Path, operation: str, function: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    try:
        return function()
    except Exception as exc:
        payload = {
            "status": "FAILED",
            "ok": False,
            "operation": operation,
            "stage": "failed",
            "error_type": type(exc).__name__,
            "error": str(exc),
            "traceback": traceback.format_exc(),
            "render": False,
        }
        atomic_write_json(progress_path, payload)
        raise
