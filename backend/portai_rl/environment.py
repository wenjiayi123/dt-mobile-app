"""Gymnasium environment calibrated by chronological port-traffic data."""

from __future__ import annotations

import math
from typing import Any, Mapping

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from .contracts import FEATURE_COLUMNS, PortDataset


DISCRETE_ACTIONS = np.asarray(
    [
        (-1.0, -1.0),
        (-1.0, 0.0),
        (-1.0, 1.0),
        (0.0, -1.0),
        (0.0, 0.0),
        (0.0, 1.0),
        (1.0, -1.0),
        (1.0, 0.0),
        (1.0, 1.0),
    ],
    dtype=np.float32,
)
OBSERVATION_SIZE = len(FEATURE_COLUMNS) + 5


class PortTrafficEnv(gym.Env[np.ndarray, Any]):
    """Data-calibrated sandbox for traffic-flow and capacity advisories.

    Historical rows supply exogenous traffic conditions. The documented response
    model applies the chosen control to congestion, throughput, and safety. It is
    a real training environment, but it is not a claim that historical AIS data
    contains counterfactual port-control outcomes.
    """

    metadata = {"render_modes": ["trajectory"], "render_fps": 4}

    def __init__(
        self,
        dataset: PortDataset,
        split: str = "train",
        *,
        discrete_actions: bool = False,
        max_steps: int = 96,
        seed: int = 42,
        render_mode: str | None = None,
        random_start: bool | None = None,
    ) -> None:
        super().__init__()
        if render_mode not in (None, "trajectory"):
            raise ValueError("render_mode must be None or 'trajectory'")
        self.dataset = dataset
        self.data = dataset.split(split)
        self.split_name = split
        self.discrete_actions = bool(discrete_actions)
        self.max_steps = max(2, min(int(max_steps), self.data.rows - 1))
        self.render_mode = render_mode
        self.random_start = split == "train" if random_start is None else bool(random_start)
        self.rng = np.random.default_rng(seed)
        self.action_space = (
            spaces.Discrete(len(DISCRETE_ACTIONS))
            if self.discrete_actions
            else spaces.Box(low=-1.0, high=1.0, shape=(2,), dtype=np.float32)
        )
        self.observation_space = spaces.Box(
            low=-10.0,
            high=10.0,
            shape=(OBSERVATION_SIZE,),
            dtype=np.float32,
        )
        environment = dataset.manifest.get("environment", {})
        reward = dataset.manifest.get("reward", {})
        self.flow_response = float(environment.get("flow_response", 0.10))
        self.capacity_response = float(environment.get("capacity_response", 0.07))
        self.action_slew = float(environment.get("action_slew", 0.35))
        self.target_congestion = float(environment.get("target_congestion", 0.38))
        self.reward_weights = {
            "throughput": float(reward.get("throughput", 1.0)),
            "congestion": float(reward.get("congestion", 1.4)),
            "safety": float(reward.get("safety", 1.8)),
            "effort": float(reward.get("effort", 0.08)),
            "slew": float(reward.get("slew", 0.12)),
        }
        self.start_index = 0
        self.index = 0
        self.steps = 0
        self.total_reward = 0.0
        self.previous_action = np.zeros(2, dtype=np.float32)
        self.current_action = np.zeros(2, dtype=np.float32)
        self.adjusted_congestion = 0.0
        self.last_metrics: dict[str, float] = {}
        self.frames: list[dict[str, Any]] = []
        self.render_calls = 0

    def reset(
        self,
        *,
        seed: int | None = None,
        options: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, dict[str, Any]]:
        super().reset(seed=seed)
        if seed is not None:
            self.rng = np.random.default_rng(seed)
        maximum_start = max(0, self.data.rows - self.max_steps - 1)
        requested_start = (options or {}).get("start_index")
        if requested_start is not None:
            self.start_index = int(requested_start)
        elif self.random_start and maximum_start > 0:
            self.start_index = int(self.rng.integers(0, maximum_start + 1))
        else:
            self.start_index = 0
        self.start_index = max(0, min(self.start_index, maximum_start))
        self.index = self.start_index
        self.steps = 0
        self.total_reward = 0.0
        self.previous_action[:] = 0.0
        self.current_action[:] = 0.0
        self.adjusted_congestion = float(self.data.raw_features[self.index, 4])
        self.last_metrics = self._metrics(self.data.raw_features[self.index], self.current_action)
        self.frames = []
        self.render_calls = 0
        self._record_frame(0.0)
        return self._observation(), self._info()

    def step(self, action: Any) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        command = (
            DISCRETE_ACTIONS[int(action)]
            if self.discrete_actions
            else np.clip(np.asarray(action, dtype=np.float32), -1.0, 1.0)
        )
        self.previous_action = self.current_action.copy()
        delta = np.clip(command - self.current_action, -self.action_slew, self.action_slew)
        self.current_action = np.clip(self.current_action + delta, -1.0, 1.0)
        self.index += 1
        self.steps += 1
        row = self.data.raw_features[self.index]
        self.last_metrics = self._metrics(row, self.current_action)
        reward = self._reward(self.last_metrics, self.current_action, delta)
        self.total_reward += reward
        terminated = self.index >= self.data.rows - 1
        truncated = self.steps >= self.max_steps and not terminated
        self._record_frame(reward)
        info = self._info()
        if terminated or truncated:
            info["episode"] = {"r": self.total_reward, "l": self.steps}
        return self._observation(), float(reward), terminated, truncated, info

    def _metrics(self, row: np.ndarray, action: np.ndarray) -> dict[str, float]:
        vessel_count, mean_sog, stopped_ratio, course_dispersion, density, _spread = [
            float(value) for value in row
        ]
        flow, capacity = [float(value) for value in action]
        congestion = np.clip(
            density - self.flow_response * flow - self.capacity_response * capacity,
            0.0,
            1.0,
        )
        throughput = np.clip(
            (mean_sog / 14.0) * (1.0 - stopped_ratio)
            + 0.08 * flow
            + 0.10 * capacity
            - 0.04 * max(flow + capacity - 1.0, 0.0),
            0.0,
            1.5,
        )
        conflict_risk = np.clip(
            0.42 * congestion
            + 0.34 * stopped_ratio
            + 0.24 * course_dispersion
            - 0.05 * flow,
            0.0,
            1.0,
        )
        safety_margin = 1.0 - conflict_risk
        self.adjusted_congestion = float(congestion)
        return {
            "vessel_count": vessel_count,
            "throughput": float(throughput),
            "congestion": float(congestion),
            "conflict_risk": float(conflict_risk),
            "safety_margin": float(safety_margin),
        }

    def _reward(self, metrics: Mapping[str, float], action: np.ndarray, delta: np.ndarray) -> float:
        safety_penalty = max(0.0, 0.45 - metrics["safety_margin"]) ** 2
        return (
            self.reward_weights["throughput"] * metrics["throughput"]
            - self.reward_weights["congestion"] * metrics["congestion"]
            - self.reward_weights["safety"] * safety_penalty
            - self.reward_weights["effort"] * float(np.square(action).sum())
            - self.reward_weights["slew"] * float(np.square(delta).sum())
        )

    def _observation(self) -> np.ndarray:
        feature = self.data.normalized_features[self.index]
        progress = self.steps / max(self.max_steps, 1)
        risk = self.last_metrics.get("conflict_risk", 0.0)
        observation = np.concatenate(
            [
                feature,
                self.current_action,
                np.asarray([progress, self.adjusted_congestion, risk], dtype=np.float32),
            ]
        )
        return observation.astype(np.float32)

    def _info(self) -> dict[str, Any]:
        return {
            "dataset_split": self.split_name,
            "dataset_sha256": self.dataset.dataset_sha256,
            "timestamp": self.data.timestamps[self.index].isoformat(),
            "step": self.steps,
            "render_mode": self.render_mode,
            **self.last_metrics,
        }

    def _record_frame(self, reward: float) -> None:
        if self.render_mode != "trajectory":
            return
        row = self.data.raw_features[self.index]
        self.frames.append(
            {
                "timestamp": self.data.timestamps[self.index].isoformat(),
                "step": self.steps,
                "vessel_count": float(row[0]),
                "mean_sog_knots": float(row[1]),
                "stopped_ratio": float(row[2]),
                "course_dispersion": float(row[3]),
                "traffic_density": float(row[4]),
                "position_spread_km": float(row[5]),
                "flow_advisory": float(self.current_action[0]),
                "capacity_allocation": float(self.current_action[1]),
                "reward": float(reward),
                **self.last_metrics,
            }
        )

    def render(self) -> list[dict[str, Any]]:
        if self.render_mode != "trajectory":
            raise RuntimeError(
                "render() is disabled during training; create a test environment with render_mode='trajectory'"
            )
        self.render_calls += 1
        return list(self.frames)


class LosPidController:
    """LOS-inspired PID controller used as the non-RL control baseline."""

    def __init__(self, kp: float, ki: float, kd: float, target: float = 0.38) -> None:
        self.kp = float(kp)
        self.ki = float(ki)
        self.kd = float(kd)
        self.target = float(target)
        self.integral = 0.0
        self.previous_error = 0.0

    def reset(self) -> None:
        self.integral = 0.0
        self.previous_error = 0.0

    def predict(self, env: PortTrafficEnv) -> np.ndarray:
        error = env.adjusted_congestion - self.target
        self.integral = float(np.clip(self.integral + error, -2.0, 2.0))
        derivative = error - self.previous_error
        self.previous_error = error
        flow = np.clip(self.kp * error + self.ki * self.integral + self.kd * derivative, -1.0, 1.0)
        count = env.last_metrics.get("vessel_count", 0.0)
        capacity = np.clip(0.5 * error + 0.015 * math.sqrt(max(count, 0.0)), -1.0, 1.0)
        return np.asarray([flow, capacity], dtype=np.float32)
