"""Subprocess entry point: train headlessly, then evaluate and record test frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .trainer import EvaluateRequest, TrainRequest, evaluate, guarded_run, train


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", type=Path, required=True)
    args = parser.parse_args()
    job = json.loads(args.job.read_text(encoding="utf-8"))
    output_dir = Path(job["output_dir"])
    progress_path = Path(job["progress_path"])
    checkpoint_path = Path(job["checkpoint_path"])
    trajectory_path = Path(job["trajectory_path"])
    train_request = TrainRequest(
        algorithm=job["algorithm"],
        manifest_path=Path(job["manifest_path"]),
        output_dir=output_dir,
        progress_path=progress_path,
        checkpoint_path=checkpoint_path,
        total_timesteps=int(job["total_timesteps"]),
        max_episode_steps=int(job.get("max_episode_steps", 96)),
        seed=int(job.get("seed", 42)),
        learning_rate=float(job.get("learning_rate", 3e-4)),
        gamma=float(job.get("gamma", 0.99)),
        batch_size=int(job.get("batch_size", 128)),
        replay_buffer_size=int(job.get("replay_buffer_size", 50_000)),
        rollout_horizon=int(job.get("rollout_horizon", 256)),
        entropy_coef=float(job.get("entropy_coef", 0.01)),
    )
    guarded_run(progress_path, "train", lambda: train(train_request))
    evaluate_request = EvaluateRequest(
        algorithm=job["algorithm"],
        manifest_path=Path(job["manifest_path"]),
        output_dir=output_dir,
        progress_path=progress_path,
        checkpoint_path=checkpoint_path,
        trajectory_path=trajectory_path,
        episodes=int(job.get("evaluation_episodes", 1)),
        max_episode_steps=int(job.get("max_episode_steps", 96)),
        seed=int(job.get("seed", 42)) + 10_000,
    )
    result = guarded_run(progress_path, "evaluate", lambda: evaluate(evaluate_request))
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
