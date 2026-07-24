#!/usr/bin/env python3
"""Aggregate official MarineCadastre AIS CSV/ZIP into port_traffic_timeseries_v1.

The output intentionally removes MMSI and vessel names. It is a reproducible,
privacy-minimised traffic time series suitable for the public replay backend.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import zipfile
from collections import defaultdict
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, TextIO


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


@contextmanager
def open_csv(path: Path) -> Iterator[TextIO]:
    if path.suffix.lower() != ".zip":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            yield handle
        return
    with zipfile.ZipFile(path) as archive:
        candidates = [name for name in archive.namelist() if name.lower().endswith(".csv")]
        if not candidates:
            raise ValueError("ZIP does not contain a CSV file")
        with archive.open(candidates[0], "r") as binary:
            import io

            with io.TextIOWrapper(binary, encoding="utf-8-sig", newline="") as handle:
                yield handle


def parse_timestamp(raw: str) -> datetime:
    parsed = datetime.fromisoformat(raw.strip().replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def bucket_time(value: datetime, interval_minutes: int) -> datetime:
    minute = value.minute - value.minute % interval_minutes
    return value.replace(minute=minute, second=0, microsecond=0)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 1.0
    index = max(0, min(len(ordered) - 1, int(round((len(ordered) - 1) * fraction))))
    return ordered[index]


def aggregate(args: argparse.Namespace) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    buckets: dict[datetime, dict[str, Any]] = defaultdict(
        lambda: {
            "vessels": set(),
            "sog": [],
            "cog": [],
            "lat": [],
            "lon": [],
            "stopped": 0,
            "messages": 0,
        }
    )
    scanned = accepted = 0
    with open_csv(args.input) as handle:
        reader = csv.DictReader(handle)
        required = {"MMSI", "BaseDateTime", "LAT", "LON", "SOG", "COG"}
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"AIS input is missing fields: {', '.join(sorted(missing))}")
        for item in reader:
            scanned += 1
            try:
                lat = float(item["LAT"])
                lon = float(item["LON"])
                sog = float(item["SOG"])
                cog = float(item["COG"])
                timestamp = parse_timestamp(item["BaseDateTime"])
            except (TypeError, ValueError):
                continue
            if not (args.min_lat <= lat <= args.max_lat and args.min_lon <= lon <= args.max_lon):
                continue
            if not (0.0 <= sog <= 80.0 and 0.0 <= cog < 360.0):
                continue
            accepted += 1
            bucket = buckets[bucket_time(timestamp, args.interval_minutes)]
            bucket["vessels"].add(item["MMSI"].strip())
            bucket["sog"].append(sog)
            bucket["cog"].append(cog)
            bucket["lat"].append(lat)
            bucket["lon"].append(lon)
            bucket["stopped"] += int(sog < args.stopped_knots)
            bucket["messages"] += 1
    if len(buckets) < 30:
        raise ValueError(
            f"bounding box produced only {len(buckets)} intervals; widen it or use a longer source period"
        )
    counts = [len(value["vessels"]) for value in buckets.values()]
    density_scale = max(percentile([float(value) for value in counts], 0.95), 1.0)
    centre_lat = (args.min_lat + args.max_lat) / 2.0
    km_per_lon = 111.32 * math.cos(math.radians(centre_lat))
    rows: list[dict[str, Any]] = []
    for timestamp in sorted(buckets):
        value = buckets[timestamp]
        messages = max(int(value["messages"]), 1)
        radians = [math.radians(course) for course in value["cog"]]
        resultant = math.sqrt(
            statistics.fmean([math.cos(angle) for angle in radians]) ** 2
            + statistics.fmean([math.sin(angle) for angle in radians]) ** 2
        )
        lat_spread = statistics.pstdev(value["lat"]) * 111.32 if len(value["lat"]) > 1 else 0.0
        lon_spread = statistics.pstdev(value["lon"]) * km_per_lon if len(value["lon"]) > 1 else 0.0
        rows.append(
            {
                "timestamp": timestamp.isoformat().replace("+00:00", "Z"),
                "vessel_count": len(value["vessels"]),
                "mean_sog_knots": round(statistics.fmean(value["sog"]), 6),
                "stopped_ratio": round(value["stopped"] / messages, 6),
                "course_dispersion": round(max(0.0, min(1.0, 1.0 - resultant)), 6),
                "traffic_density": round(min(len(value["vessels"]) / density_scale, 1.0), 6),
                "position_spread_km": round(math.hypot(lat_spread, lon_spread), 6),
            }
        )
    evidence = {
        "source_sha256": sha256_file(args.input),
        "source_rows_scanned": scanned,
        "source_rows_in_bbox": accepted,
        "output_intervals": len(rows),
        "aggregation_interval_minutes": args.interval_minutes,
        "bbox_wgs84": [args.min_lon, args.min_lat, args.max_lon, args.max_lat],
        "identity_fields_removed": True,
    }
    return rows, evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence-output", type=Path, required=True)
    parser.add_argument("--min-lat", type=float, required=True)
    parser.add_argument("--max-lat", type=float, required=True)
    parser.add_argument("--min-lon", type=float, required=True)
    parser.add_argument("--max-lon", type=float, required=True)
    parser.add_argument("--interval-minutes", type=int, default=5)
    parser.add_argument("--stopped-knots", type=float, default=0.5)
    args = parser.parse_args()
    if args.interval_minutes <= 0 or 60 % args.interval_minutes:
        raise SystemExit("--interval-minutes must be a positive divisor of 60")
    rows, evidence = aggregate(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    evidence["output_sha256"] = sha256_file(args.output)
    args.evidence_output.parent.mkdir(parents=True, exist_ok=True)
    args.evidence_output.write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(evidence, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
