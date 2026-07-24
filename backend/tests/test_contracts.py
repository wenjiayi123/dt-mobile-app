from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pytest

from portai_rl.contracts import ALGORITHM_IDS, FEATURE_COLUMNS, load_dataset


def make_manifest(tmp_path: Path, rows: int = 80) -> Path:
    csv_path = tmp_path / "traffic.csv"
    start = datetime(2024, 1, 1, tzinfo=timezone.utc)
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["timestamp", *FEATURE_COLUMNS])
        writer.writeheader()
        for index in range(rows):
            writer.writerow(
                {
                    "timestamp": (start + timedelta(minutes=5 * index)).isoformat(),
                    "vessel_count": 5 + index % 11,
                    "mean_sog_knots": 3.0 + (index % 7) * 0.4,
                    "stopped_ratio": 0.1 + (index % 5) * 0.03,
                    "course_dispersion": 0.2 + (index % 4) * 0.04,
                    "traffic_density": 0.25 + (index % 9) * 0.05,
                    "position_spread_km": 0.8 + (index % 6) * 0.1,
                }
            )
    sha = hashlib.sha256(csv_path.read_bytes()).hexdigest()
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schema_version": "port_traffic_timeseries_v1",
                "dataset_id": "test-fixture",
                "name": "test fixture",
                "data_file": "traffic.csv",
                "data_sha256": sha,
                "split": {"train_ratio": 0.7, "validation_ratio": 0.15, "test_ratio": 0.15},
                "source": {"type": "test_fixture"},
            }
        ),
        encoding="utf-8",
    )
    return manifest_path


def test_exact_five_algorithm_contract() -> None:
    assert ALGORITHM_IDS == ("ppo", "sac", "td3", "dqn", "los_pid")


def test_chronological_splits_and_train_only_scaler(tmp_path: Path) -> None:
    dataset = load_dataset(make_manifest(tmp_path))
    assert dataset.train.timestamps[-1] < dataset.validation.timestamps[0]
    assert dataset.validation.timestamps[-1] < dataset.test.timestamps[0]
    assert np.allclose(dataset.train.raw_features.mean(axis=0), dataset.feature_mean)
    assert dataset.status()["training_render_mode"] is None
    assert dataset.status()["splits"]["test"]["rows"] > 0


def test_sha_mismatch_fails_closed(tmp_path: Path) -> None:
    manifest = make_manifest(tmp_path)
    value = json.loads(manifest.read_text(encoding="utf-8"))
    value["data_sha256"] = "0" * 64
    manifest.write_text(json.dumps(value), encoding="utf-8")
    with pytest.raises(ValueError, match="SHA-256 mismatch"):
        load_dataset(manifest)
