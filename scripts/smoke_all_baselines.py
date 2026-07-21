#!/usr/bin/env python3
"""Run a short wiring smoke for all five baselines; not a convergence claim."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "backend"))

from portai_rl.contracts import ALGORITHM_IDS  # noqa: E402
from portai_rl.trainer import EvaluateRequest, TrainRequest, evaluate, train  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=PROJECT_ROOT / "backend/config/public_noaa_ais.json")
    parser.add_argument("--output", type=Path, default=PROJECT_ROOT / "backend/artifacts/smoke")
    parser.add_argument("--timesteps", type=int, default=128)
    args = parser.parse_args()
    summaries = []
    for algorithm in ALGORITHM_IDS:
        run_dir = args.output / algorithm
        progress = run_dir / "progress.json"
        checkpoint = run_dir / "checkpoint.json"
        trajectory = run_dir / "test_trajectory.json"
        training = train(
            TrainRequest(
                algorithm=algorithm,
                manifest_path=args.manifest,
                output_dir=run_dir,
                progress_path=progress,
                checkpoint_path=checkpoint,
                total_timesteps=args.timesteps,
                max_episode_steps=24,
                batch_size=32,
                rollout_horizon=64,
                replay_buffer_size=1_000,
            )
        )
        test = evaluate(
            EvaluateRequest(
                algorithm=algorithm,
                manifest_path=args.manifest,
                output_dir=run_dir,
                progress_path=progress,
                checkpoint_path=checkpoint,
                trajectory_path=trajectory,
                max_episode_steps=24,
            )
        )
        summaries.append(
            {
                "algorithm": algorithm,
                "training_status": training["status"],
                "test_status": test["status"],
                "mean_reward": test["aggregate_metrics"]["mean_reward"],
                "smoke_only": True,
            }
        )
    print(json.dumps(summaries, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
