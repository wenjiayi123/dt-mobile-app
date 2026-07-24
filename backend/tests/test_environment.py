from __future__ import annotations

import numpy as np
import pytest

from portai_rl.contracts import load_dataset
from portai_rl.environment import OBSERVATION_SIZE, LosPidController, PortTrafficEnv
from test_contracts import make_manifest


def test_training_environment_cannot_render(tmp_path) -> None:
    dataset = load_dataset(make_manifest(tmp_path))
    env = PortTrafficEnv(dataset, split="train", max_steps=10, render_mode=None)
    observation, _ = env.reset()
    assert observation.shape == (OBSERVATION_SIZE,)
    for _ in range(3):
        observation, reward, _, _, info = env.step(np.zeros(2, dtype=np.float32))
        assert np.isfinite(reward)
        assert info["dataset_split"] == "train"
    assert env.frames == []
    with pytest.raises(RuntimeError, match="disabled during training"):
        env.render()


def test_test_split_records_frames_only_after_training(tmp_path) -> None:
    dataset = load_dataset(make_manifest(tmp_path))
    env = PortTrafficEnv(dataset, split="test", max_steps=8, render_mode="trajectory", random_start=False)
    env.reset()
    controller = LosPidController(1.2, 0.02, 0.18)
    controller.reset()
    terminated = truncated = False
    while not (terminated or truncated):
        _, _, terminated, truncated, _ = env.step(controller.predict(env))
    frames = env.render()
    assert len(frames) == env.steps + 1
    assert all(frame["timestamp"] for frame in frames)
    assert env.render_calls == 1
