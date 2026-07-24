from __future__ import annotations

import json

import pytest

from portai_rl.trainer import (
    EvaluateRequest,
    TrainRequest,
    _resolve_run_artifact,
    evaluate,
    train,
)
from test_contracts import make_manifest


def test_los_pid_calibrates_train_then_evaluates_test(tmp_path) -> None:
    manifest = make_manifest(tmp_path, rows=120)
    output = tmp_path / "run"
    progress = output / "progress.json"
    checkpoint = output / "checkpoint.json"
    train_result = train(
        TrainRequest(
            algorithm="los_pid",
            manifest_path=manifest,
            output_dir=output,
            progress_path=progress,
            checkpoint_path=checkpoint,
            total_timesteps=64,
            max_episode_steps=20,
        )
    )
    assert train_result["dataset_split"] == "train"
    assert train_result["render"] is False
    assert json.loads(checkpoint.read_text())["dataset_split_used"] == "train"
    trajectory = output / "test_trajectory.json"
    evaluation = evaluate(
        EvaluateRequest(
            algorithm="los_pid",
            manifest_path=manifest,
            output_dir=output,
            progress_path=progress,
            checkpoint_path=checkpoint,
            trajectory_path=trajectory,
            max_episode_steps=20,
        )
    )
    assert evaluation["dataset_split"] == "test"
    assert evaluation["render_ready"] is True
    replay = json.loads(trajectory.read_text())
    assert replay["format"] == "portai_policy_test_rollout_v1"
    assert replay["rendered_after_training"] is True
    assert replay["frames"]


def test_training_artifact_paths_cannot_escape_run_directory(tmp_path) -> None:
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    outside = tmp_path / "outside.json"
    outside.write_text("{}")
    with pytest.raises(ValueError, match="escapes"):
        _resolve_run_artifact(outside, run_dir, label="training history path")
