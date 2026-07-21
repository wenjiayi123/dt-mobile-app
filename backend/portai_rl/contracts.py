"""Versioned contracts shared by ingestion, training, evaluation, and the API."""

from __future__ import annotations

import csv
import hashlib
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

import numpy as np


RL_ALGORITHMS = ("ppo", "sac", "td3", "dqn")
CONTROL_ALGORITHMS = ("los_pid",)
ALGORITHM_IDS = RL_ALGORITHMS + CONTROL_ALGORITHMS

DATASET_SCHEMA = "port_traffic_timeseries_v1"
FEATURE_COLUMNS = (
    "vessel_count",
    "mean_sog_knots",
    "stopped_ratio",
    "course_dispersion",
    "traffic_density",
    "position_spread_km",
)
REQUIRED_COLUMNS = ("timestamp",) + FEATURE_COLUMNS


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_sha256(value: Mapping[str, Any]) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def atomic_write_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temporary.replace(path)


def parse_timestamp(raw: str) -> datetime:
    normalized = raw.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


@dataclass(frozen=True)
class DatasetSplit:
    name: str
    timestamps: tuple[datetime, ...]
    raw_features: np.ndarray
    normalized_features: np.ndarray

    @property
    def rows(self) -> int:
        return len(self.timestamps)


@dataclass(frozen=True)
class PortDataset:
    manifest_path: Path
    csv_path: Path
    manifest: Mapping[str, Any]
    dataset_sha256: str
    experiment_sha256: str
    train: DatasetSplit
    validation: DatasetSplit
    test: DatasetSplit
    feature_mean: np.ndarray
    feature_std: np.ndarray

    def split(self, name: str) -> DatasetSplit:
        if name == "train":
            return self.train
        if name == "validation":
            return self.validation
        if name == "test":
            return self.test
        raise ValueError(f"unknown dataset split: {name}")

    def status(self) -> dict[str, Any]:
        source = dict(self.manifest.get("source", {}))
        return {
            "schema_version": DATASET_SCHEMA,
            "dataset_id": self.manifest.get("dataset_id"),
            "name": self.manifest.get("name"),
            "evidence_level": self.manifest.get(
                "evidence_level", "historical_public_replay"
            ),
            "live_data_verified": bool(self.manifest.get("live_data_verified", False)),
            "source": source,
            "dataset_sha256": self.dataset_sha256,
            "experiment_sha256": self.experiment_sha256,
            "features": list(FEATURE_COLUMNS),
            "splits": {
                "train": _split_status(self.train),
                "validation": _split_status(self.validation),
                "test": _split_status(self.test),
            },
            "training_render_mode": None,
            "evaluation_render_mode": "recorded_test_trajectory",
        }


def _split_status(split: DatasetSplit) -> dict[str, Any]:
    return {
        "rows": split.rows,
        "start": split.timestamps[0].isoformat(),
        "end": split.timestamps[-1].isoformat(),
    }


def _load_rows(csv_path: Path) -> tuple[tuple[datetime, ...], np.ndarray]:
    timestamps: list[datetime] = []
    rows: list[list[float]] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [name for name in REQUIRED_COLUMNS if name not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"dataset is missing required columns: {', '.join(missing)}")
        for line_number, item in enumerate(reader, start=2):
            try:
                timestamp = parse_timestamp(item["timestamp"])
                features = [float(item[name]) for name in FEATURE_COLUMNS]
            except (KeyError, TypeError, ValueError) as exc:
                raise ValueError(f"invalid dataset row {line_number}: {exc}") from exc
            if not all(math.isfinite(value) for value in features):
                raise ValueError(f"dataset row {line_number} contains a non-finite value")
            timestamps.append(timestamp)
            rows.append(features)
    if len(rows) < 30:
        raise ValueError("dataset needs at least 30 chronological rows")
    if any(current <= previous for previous, current in zip(timestamps, timestamps[1:])):
        raise ValueError("timestamps must be strictly increasing; sort/deduplicate before training")
    return tuple(timestamps), np.asarray(rows, dtype=np.float32)


def load_dataset(manifest_path: str | Path) -> PortDataset:
    path = Path(manifest_path).expanduser().resolve()
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != DATASET_SCHEMA:
        raise ValueError(
            f"expected schema_version={DATASET_SCHEMA!r}, got {manifest.get('schema_version')!r}"
        )
    csv_value = str(manifest.get("data_file", "")).strip()
    if not csv_value:
        raise ValueError("manifest.data_file is required")
    csv_path = (path.parent / csv_value).resolve()
    if not csv_path.exists():
        raise FileNotFoundError(f"dataset file does not exist: {csv_path}")
    actual_sha256 = sha256_file(csv_path)
    expected_sha256 = str(manifest.get("data_sha256", "")).strip()
    if expected_sha256 and actual_sha256 != expected_sha256:
        raise ValueError(
            "dataset SHA-256 mismatch; update the manifest deliberately after reviewing the data"
        )
    timestamps, raw = _load_rows(csv_path)
    split_config = manifest.get("split", {})
    train_ratio = float(split_config.get("train_ratio", 0.70))
    validation_ratio = float(split_config.get("validation_ratio", 0.15))
    test_ratio = float(split_config.get("test_ratio", 0.15))
    if not math.isclose(train_ratio + validation_ratio + test_ratio, 1.0, abs_tol=1e-9):
        raise ValueError("train/validation/test ratios must add up to 1")
    if min(train_ratio, validation_ratio, test_ratio) <= 0:
        raise ValueError("every chronological split must be non-empty")
    train_end = max(10, int(len(raw) * train_ratio))
    validation_end = max(train_end + 5, int(len(raw) * (train_ratio + validation_ratio)))
    if validation_end >= len(raw) - 4:
        raise ValueError("dataset is too small for independent validation and test splits")
    feature_mean = raw[:train_end].mean(axis=0)
    feature_std = raw[:train_end].std(axis=0)
    feature_std = np.where(feature_std < 1e-6, 1.0, feature_std)
    normalized = np.clip((raw - feature_mean) / feature_std, -8.0, 8.0).astype(np.float32)

    def make_split(name: str, start: int, end: int) -> DatasetSplit:
        return DatasetSplit(
            name=name,
            timestamps=timestamps[start:end],
            raw_features=raw[start:end].copy(),
            normalized_features=normalized[start:end].copy(),
        )

    experiment_payload = {
        "dataset_sha256": actual_sha256,
        "schema_version": DATASET_SCHEMA,
        "features": FEATURE_COLUMNS,
        "split": split_config,
        "environment": manifest.get("environment", {}),
        "reward": manifest.get("reward", {}),
    }
    return PortDataset(
        manifest_path=path,
        csv_path=csv_path,
        manifest=manifest,
        dataset_sha256=actual_sha256,
        experiment_sha256=canonical_sha256(experiment_payload),
        train=make_split("train", 0, train_end),
        validation=make_split("validation", train_end, validation_end),
        test=make_split("test", validation_end, len(raw)),
        feature_mean=feature_mean,
        feature_std=feature_std,
    )
