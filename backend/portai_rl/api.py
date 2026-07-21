"""FastAPI control plane for real training, evaluation, replay, and evidence."""

from __future__ import annotations

import asyncio
import hashlib
import html
import json
import math
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

import httpx
from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from .contracts import ALGORITHM_IDS, atomic_write_json, load_dataset


BACKEND_ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS_ROOT = Path(os.getenv("PORTAI_ARTIFACTS_DIR", BACKEND_ROOT / "artifacts")).resolve()
MANIFEST_PATH = Path(
    os.getenv("PORTAI_DATASET_MANIFEST", BACKEND_ROOT / "config" / "public_noaa_ais.json")
).resolve()
REQUESTS_PATH = ARTIFACTS_ROOT / "requests.json"
AUDIT_PATH = ARTIFACTS_ROOT / "audit_events.jsonl"
CONTROL_CONFIG_PATH = ARTIFACTS_ROOT / "control_config.json"
SERVER_HOST = os.getenv("PORTAI_HOST", "127.0.0.1")
SERVER_PORT = int(os.getenv("PORTAI_PORT", "8000"))
APP_ENV = os.getenv("PORTAI_APP_ENV", "research").strip().lower()
API_KEY = os.getenv("PORTAI_API_KEY", "").strip()
PANEL_HOST = "127.0.0.1" if SERVER_HOST in {"0.0.0.0", "::"} else SERVER_HOST
PANEL_URL = os.getenv("PORTAI_PANEL_URL", f"http://{PANEL_HOST}:{SERVER_PORT}/rl-panel")
LIVE_MODE = os.getenv("PORTAI_DATA_MODE", "public_replay").strip().lower() == "live"
LIVE_DATA_VERIFIED = os.getenv("PORTAI_LIVE_DATA_VERIFIED", "false").strip().lower() == "true"
EXECUTION_ADAPTER_VERIFIED = (
    os.getenv("PORTAI_EXECUTION_ADAPTER_VERIFIED", "false").strip().lower() == "true"
)
EXECUTION_ADAPTER_URL = os.getenv("PORTAI_EXECUTION_ADAPTER_URL", "").strip()
EXECUTION_ADAPTER_TOKEN = os.getenv("PORTAI_EXECUTION_ADAPTER_TOKEN", "").strip()
LIVE_SNAPSHOT_URL = os.getenv("PORTAI_LIVE_SNAPSHOT_URL", "").strip()
LIVE_ALERTS_URL = os.getenv("PORTAI_LIVE_ALERTS_URL", "").strip()
LIVE_GATEWAY_TOKEN = os.getenv("PORTAI_LIVE_GATEWAY_TOKEN", "").strip()
MAX_TRAINING_TIMESTEPS = int(os.getenv("PORTAI_MAX_TRAINING_TIMESTEPS", "5000000"))
MAX_CONCURRENT_TRAINING = int(os.getenv("PORTAI_MAX_CONCURRENT_TRAINING", "1"))
MAX_REQUEST_BYTES = int(os.getenv("PORTAI_MAX_REQUEST_BYTES", "262144"))
CORS_ORIGINS = [
    value.strip()
    for value in os.getenv(
        "PORTAI_CORS_ORIGINS",
        "http://localhost:8765,http://127.0.0.1:8765",
    ).split(",")
    if value.strip()
]
PRODUCTION_MODE = APP_ENV == "production" or LIVE_MODE

if PRODUCTION_MODE and len(API_KEY) < 32:
    raise RuntimeError("production/live mode requires PORTAI_API_KEY with at least 32 characters")
if PRODUCTION_MODE and "*" in CORS_ORIGINS:
    raise RuntimeError("production/live mode forbids wildcard CORS origins")
if MAX_CONCURRENT_TRAINING < 1:
    raise RuntimeError("PORTAI_MAX_CONCURRENT_TRAINING must be positive")
if MAX_TRAINING_TIMESTEPS < 64:
    raise RuntimeError("PORTAI_MAX_TRAINING_TIMESTEPS must be at least 64")

ALGORITHM_LABELS = {
    "ppo": "PPO",
    "sac": "SAC",
    "td3": "TD3",
    "dqn": "DQN",
    "los_pid": "LOS-PID",
}
_store_lock = threading.RLock()
_panel_last_seen = 0.0
_IDENTIFIER_PATTERN = re.compile(r"^(?:req|job)-[a-f0-9]{12}$")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _validate_identifier(value: str, *, prefix: str) -> str:
    normalized = str(value).strip()
    if not _IDENTIFIER_PATTERN.fullmatch(normalized) or not normalized.startswith(f"{prefix}-"):
        raise HTTPException(status_code=422, detail=f"invalid {prefix} identifier")
    return normalized


def _job_dir(job_id: str) -> Path:
    normalized = _validate_identifier(job_id, prefix="job")
    root = ARTIFACTS_ROOT.resolve()
    candidate = (root / normalized).resolve()
    if candidate.parent != root:
        raise HTTPException(status_code=422, detail="job identifier escapes artifact root")
    return candidate


def _bounded_json(value: Any, *, label: str) -> None:
    try:
        size = len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"{label} must be JSON serializable") from exc
    if size > MAX_REQUEST_BYTES:
        raise HTTPException(status_code=413, detail=f"{label} exceeds {MAX_REQUEST_BYTES} bytes")


def _config_int(config: Mapping[str, Any], key: str, default: int, low: int, high: int) -> int:
    try:
        value = int(config.get(key, default))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"{key} must be an integer") from exc
    if not low <= value <= high:
        raise HTTPException(status_code=422, detail=f"{key} must be between {low} and {high}")
    return value


def _config_float(
    config: Mapping[str, Any], key: str, default: float, low: float, high: float
) -> float:
    try:
        value = float(config.get(key, default))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"{key} must be numeric") from exc
    if not math.isfinite(value) or not low <= value <= high:
        raise HTTPException(status_code=422, detail=f"{key} must be between {low} and {high}")
    return value


def _validated_training_config(config: Mapping[str, Any], dataset_sha256: str) -> dict[str, Any]:
    _bounded_json(config, label="training config")
    if len(config) > 48:
        raise HTTPException(status_code=422, detail="training config contains too many fields")
    algorithm = str(config.get("algorithm", "")).strip().lower()
    if algorithm not in ALGORITHM_IDS:
        raise HTTPException(status_code=422, detail=f"algorithm must be one of {ALGORITHM_IDS}")
    requested_sha = str(config.get("dataset_sha256", "")).strip()
    if requested_sha and requested_sha != dataset_sha256:
        raise HTTPException(status_code=409, detail="client dataset hash does not match server dataset")
    total_steps = _config_int(
        config,
        "total_steps",
        15 if algorithm == "los_pid" else 20_000,
        1 if algorithm == "los_pid" else 64,
        30 if algorithm == "los_pid" else MAX_TRAINING_TIMESTEPS,
    )
    return {
        **config,
        "algorithm": algorithm,
        "total_steps": total_steps,
        "max_episode_steps": _config_int(config, "max_episode_steps", 96, 2, 512),
        "evaluation_episodes": _config_int(config, "evaluation_episodes", 1, 1, 5),
        "seed": _config_int(config, "seed", 42, 0, 2_147_483_647),
        "batch_size": _config_int(config, "batch_size", 128, 16, 4096),
        "replay_buffer": _config_int(config, "replay_buffer", 50_000, 1_000, 10_000_000),
        "rollout_horizon": _config_int(config, "rollout_horizon", 256, 8, 4096),
        "learning_rate": _config_float(config, "learning_rate", 3e-4, 1e-8, 1.0),
        "gamma": _config_float(config, "gamma", 0.99, 0.0, 1.0),
        "entropy_coef": _config_float(config, "entropy_coef", 0.01, 0.0, 1.0),
    }


def _read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def _load_requests() -> dict[str, dict[str, Any]]:
    value = _read_json(REQUESTS_PATH, {})
    return value if isinstance(value, dict) else {}


def _save_requests(value: Mapping[str, Any]) -> None:
    atomic_write_json(REQUESTS_PATH, value)


def _dataset():
    try:
        return load_dataset(MANIFEST_PATH)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"dataset unavailable: {exc}") from exc


def _production_dispatch_ready() -> bool:
    return bool(
        LIVE_MODE
        and LIVE_DATA_VERIFIED
        and EXECUTION_ADAPTER_VERIFIED
        and EXECUTION_ADAPTER_URL
        and LIVE_SNAPSHOT_URL
    )


def _progress_for(job: Mapping[str, Any]) -> dict[str, Any]:
    progress = _read_json(Path(job["progress_path"]), {})
    if not progress:
        return {
            "status": "APPROVED",
            "stage": "worker_starting",
            "progress": 0.0,
            "step": 0,
            "total_steps": int(job["total_timesteps"]),
            "render": False,
            "render_mode": None,
            "dataset_split": "train",
        }
    return progress


def _active_training_count(requests: Mapping[str, Mapping[str, Any]]) -> int:
    active = 0
    for record in requests.values():
        job_path_value = record.get("job_path")
        if not job_path_value:
            continue
        job = _read_json(Path(str(job_path_value)), {})
        if not job:
            continue
        status = str(_progress_for(job).get("status", "")).upper()
        if status not in {"COMPLETED", "FAILED", "REJECTED"}:
            active += 1
    return active


class TrainingRequestPayload(BaseModel):
    source: str = Field(default="dt_mobile_app", min_length=1, max_length=64)
    requested_by: str = Field(default="mobile_operator", min_length=1, max_length=120)
    config: dict[str, Any] = Field(min_length=1, max_length=48)
    scenario_snapshot: dict[str, Any] = Field(default_factory=dict, max_length=64)
    policy_context: dict[str, Any] = Field(default_factory=dict, max_length=64)


class ApprovalPayload(BaseModel):
    approved_by: str = Field(default="desktop_operator", min_length=1, max_length=120)


class RejectionPayload(BaseModel):
    rejected_by: str = Field(default="desktop_operator", min_length=1, max_length=120)
    reason: str = Field(default="operator_rejected", min_length=1, max_length=512)


app = FastAPI(
    title="PortAI Real RL Service",
    version="3.0.0",
    description="Headless train / held-out test / recorded replay service",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_origin_regex=(
        None if PRODUCTION_MODE else r"https?://(localhost|127\.0\.0\.1)(:\d+)?"
    ),
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=[
        "Accept",
        "Authorization",
        "Content-Type",
        "X-Client-App",
        "X-Client-Mode",
        "X-Client-Platform",
        "X-App-Env",
    ],
)


@app.middleware("http")
async def api_key_gate(request: Request, call_next):
    if not API_KEY or request.method == "OPTIONS" or request.url.path == "/health":
        return await call_next(request)
    authorization = request.headers.get("authorization", "")
    scheme, _, supplied = authorization.partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(supplied, API_KEY):
        return JSONResponse(
            status_code=401,
            content={"detail": "valid bearer token required"},
            headers={"WWW-Authenticate": "Bearer"},
        )
    return await call_next(request)


@app.get("/health")
def health() -> dict[str, Any]:
    dataset_ready = True
    dataset_error = None
    try:
        status = load_dataset(MANIFEST_PATH).status()
    except Exception as exc:
        dataset_ready = False
        dataset_error = str(exc)
        status = None
    live_gate = not LIVE_MODE or (LIVE_DATA_VERIFIED and bool(LIVE_SNAPSHOT_URL))
    return {
        "ok": dataset_ready and live_gate,
        "service": "portai-real-rl",
        "version": app.version,
        "app_env": APP_ENV,
        "api_key_required": bool(API_KEY),
        "data_mode": "live" if LIVE_MODE else "public_replay",
        "live_data_verified": LIVE_DATA_VERIFIED,
        "execution_adapter_verified": EXECUTION_ADAPTER_VERIFIED,
        "production_dispatch_enabled": _production_dispatch_ready(),
        "max_concurrent_training": MAX_CONCURRENT_TRAINING,
        "dataset_ready": dataset_ready,
        "dataset_error": dataset_error,
        "dataset": status,
    }


@app.get("/api/data/status")
def data_status() -> dict[str, Any]:
    status = _dataset().status()
    status.update(
        {
            "mode": "live" if LIVE_MODE else "public_replay",
            "production_dispatch_enabled": _production_dispatch_ready(),
            "declaration": (
                "verified live data gateway; execution remains separately gated"
                if LIVE_MODE and LIVE_DATA_VERIFIED
                else "public historical replay; not live port telemetry"
            ),
        }
    )
    if LIVE_MODE and (not LIVE_DATA_VERIFIED or not LIVE_SNAPSHOT_URL):
        raise HTTPException(
            status_code=503,
            detail="live mode fails closed until data is verified and a live snapshot adapter is configured",
        )
    return status


@app.get("/api/rl/train/baselines")
def baselines() -> dict[str, Any]:
    return {
        "items": [
            {
                "id": algorithm,
                "label": ALGORITHM_LABELS[algorithm],
                "family": "reinforcement_learning" if algorithm != "los_pid" else "control_theory",
                "library": "stable-baselines3" if algorithm != "los_pid" else "native LOS-PID",
                "action_space": "discrete_9" if algorithm == "dqn" else "continuous_box_2",
            }
            for algorithm in ALGORITHM_IDS
        ],
        "count": 5,
        "contract": "four_rl_plus_one_control",
        "training_render_mode": None,
        "evaluation_render_mode": "recorded_test_trajectory",
        "dataset": _dataset().status(),
    }


@app.post("/api/rl/train/requests")
def create_training_request(payload: TrainingRequestPayload) -> dict[str, Any]:
    dataset = _dataset()
    _bounded_json(payload.model_dump(), label="training request")
    config = _validated_training_config(payload.config, dataset.dataset_sha256)
    request_id = f"req-{uuid.uuid4().hex[:12]}"
    record = {
        "request_id": request_id,
        "status": "waiting_approval",
        "source": payload.source.strip(),
        "requested_by": payload.requested_by.strip(),
        "config": config,
        "scenario_snapshot": payload.scenario_snapshot,
        "policy_context": payload.policy_context,
        "created_at": utc_now(),
        "job_id": None,
    }
    with _store_lock:
        requests = _load_requests()
        requests[request_id] = record
        _save_requests(requests)
    return {"request_id": request_id, "status": "waiting_approval", "created_at": record["created_at"]}


def _job_payload(record: Mapping[str, Any], job_id: str, job_dir: Path) -> dict[str, Any]:
    config = record["config"]
    algorithm = str(config["algorithm"]).lower()
    total_steps = int(config.get("total_steps", 20_000))
    if algorithm != "los_pid" and total_steps < 64:
        raise HTTPException(status_code=422, detail="RL training requires at least 64 timesteps")
    return {
        "format": "portai_training_job_v1",
        "job_id": job_id,
        "request_id": record["request_id"],
        "algorithm": algorithm,
        "manifest_path": os.fspath(MANIFEST_PATH),
        "output_dir": os.fspath(job_dir),
        "progress_path": os.fspath(job_dir / "progress.json"),
        "checkpoint_path": os.fspath(job_dir / "checkpoint.json"),
        "trajectory_path": os.fspath(job_dir / "test_trajectory.json"),
        "total_timesteps": total_steps,
        "max_episode_steps": int(config.get("max_episode_steps", 96)),
        "evaluation_episodes": int(config.get("evaluation_episodes", 1)),
        "seed": int(config.get("seed", 42)),
        "learning_rate": float(config.get("learning_rate", 3e-4)),
        "gamma": float(config.get("gamma", 0.99)),
        "batch_size": int(config.get("batch_size", 128)),
        "replay_buffer_size": int(config.get("replay_buffer", 50_000)),
        "rollout_horizon": int(config.get("rollout_horizon", 256)),
        "entropy_coef": float(config.get("entropy_coef", 0.01)),
        "created_at": utc_now(),
    }


@app.post("/api/rl/train/requests/{request_id}/approve")
def approve_training_request(request_id: str, payload: ApprovalPayload) -> dict[str, Any]:
    request_id = _validate_identifier(request_id, prefix="req")
    with _store_lock:
        requests = _load_requests()
        record = requests.get(request_id)
        if record is None:
            raise HTTPException(status_code=404, detail="training request not found")
        if record.get("status") != "waiting_approval":
            raise HTTPException(status_code=409, detail="request is not waiting for approval")
        approved_by = payload.approved_by.strip()
        if approved_by.casefold() == str(record.get("requested_by", "")).strip().casefold():
            raise HTTPException(
                status_code=409,
                detail="approver must be different from the requester",
            )
        if _active_training_count(requests) >= MAX_CONCURRENT_TRAINING:
            raise HTTPException(status_code=429, detail="maximum concurrent training jobs reached")
        job_id = f"job-{uuid.uuid4().hex[:12]}"
        job_dir = _job_dir(job_id)
        job_dir.mkdir(parents=True, exist_ok=False)
        job = _job_payload(record, job_id, job_dir)
        job_path = job_dir / "job.json"
        atomic_write_json(job_path, job)
        log_handle = (job_dir / "worker.log").open("ab")
        environment = dict(os.environ)
        environment["PYTHONPATH"] = os.fspath(BACKEND_ROOT) + os.pathsep + environment.get("PYTHONPATH", "")
        process = subprocess.Popen(
            [sys.executable, "-m", "portai_rl.worker", "--job", os.fspath(job_path)],
            cwd=BACKEND_ROOT,
            env=environment,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        log_handle.close()
        job["pid"] = process.pid
        atomic_write_json(job_path, job)
        record.update(
            {
                "status": "approved",
                "approved_by": approved_by,
                "approved_at": utc_now(),
                "job_id": job_id,
                "job_path": os.fspath(job_path),
            }
        )
        requests[request_id] = record
        _save_requests(requests)
    return {"request_id": request_id, "status": "approved", "job_id": job_id, "pid": process.pid}


@app.post("/api/rl/train/requests/{request_id}/reject")
def reject_training_request(request_id: str, payload: RejectionPayload) -> dict[str, Any]:
    request_id = _validate_identifier(request_id, prefix="req")
    with _store_lock:
        requests = _load_requests()
        record = requests.get(request_id)
        if record is None:
            raise HTTPException(status_code=404, detail="training request not found")
        if record.get("status") != "waiting_approval":
            raise HTTPException(status_code=409, detail="request is not waiting for approval")
        record.update(
            {
                "status": "rejected",
                "rejected_by": payload.rejected_by,
                "rejection_reason": payload.reason,
                "rejected_at": utc_now(),
            }
        )
        requests[request_id] = record
        _save_requests(requests)
    return {"request_id": request_id, "status": "rejected"}


@app.get("/api/rl/train/requests/{request_id}")
def get_training_request(request_id: str) -> dict[str, Any]:
    request_id = _validate_identifier(request_id, prefix="req")
    requests = _load_requests()
    record = requests.get(request_id)
    if record is None:
        raise HTTPException(status_code=404, detail="training request not found")
    response = dict(record)
    if record.get("job_path"):
        job = _read_json(Path(record["job_path"]), {})
        response["training_status"] = _progress_for(job)
    return response


@app.get("/api/rl/train/status")
def get_training_status(job_id: str) -> dict[str, Any]:
    job_id = _validate_identifier(job_id, prefix="job")
    job_path = _job_dir(job_id) / "job.json"
    job = _read_json(job_path, None)
    if job is None:
        raise HTTPException(status_code=404, detail="training job not found")
    return {"job_id": job_id, "status": _progress_for(job)}


@app.get("/api/rl/artifacts/{job_id}/replay")
def get_test_replay(job_id: str) -> dict[str, Any]:
    job_id = _validate_identifier(job_id, prefix="job")
    path = _job_dir(job_id) / "test_trajectory.json"
    value = _read_json(path, None)
    if value is None:
        raise HTTPException(status_code=409, detail="held-out test replay is not ready")
    return value


@app.post("/api/rl/future/run")
def run_future_replay(payload: dict[str, Any]) -> dict[str, Any]:
    del payload
    completed = _completed_jobs()
    if not completed:
        raise HTTPException(status_code=409, detail="train and evaluate a policy first")
    latest = completed[-1]
    trajectory = _read_json(Path(latest["trajectory_path"]), {})
    return {
        "source": "held_out_test_replay",
        "job_id": latest["job_id"],
        "algorithm": latest["algorithm"],
        "dataset_split": "test",
        "frames": trajectory.get("frames", []),
        "aggregate_metrics": trajectory.get("aggregate_metrics", {}),
    }


@app.post("/api/rl/desktop/launch")
def launch_desktop_panel() -> dict[str, Any]:
    if os.getenv("PORTAI_ALLOW_BROWSER_LAUNCH", "true").lower() != "true":
        return {"launched": False, "url": PANEL_URL, "message": "browser launch disabled; open URL manually"}
    launched = bool(webbrowser.open(PANEL_URL, new=1, autoraise=True))
    return {
        "launched": launched,
        "url": PANEL_URL,
        "message": "browser open request accepted" if launched else "browser did not accept open request",
    }


@app.get("/api/rl/desktop/status")
def desktop_status() -> dict[str, Any]:
    active = time.monotonic() - _panel_last_seen < 20.0
    return {
        "panel_active": active,
        "url": PANEL_URL,
        "message": "desktop approval panel heartbeat is active" if active else "open the desktop approval panel",
    }


def _completed_jobs() -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for job_path in sorted(ARTIFACTS_ROOT.glob("job-*/job.json")):
        try:
            job_dir = _job_dir(job_path.parent.name)
        except HTTPException:
            continue
        if job_path.resolve() != (job_dir / "job.json").resolve():
            continue
        job = _read_json(job_path, {})
        progress = _progress_for(job) if job else {}
        if progress.get("status") == "COMPLETED":
            result.append({**job, "progress": progress})
    return result


@app.get("/api/strategy/candidates")
def strategy_candidates() -> dict[str, Any]:
    completed = _completed_jobs()
    if not completed:
        return {
            "items": [],
            "source": "no_completed_test_artifact",
            "message": "No strategy candidate exists until a policy completes held-out testing.",
        }
    by_algorithm: dict[str, dict[str, Any]] = {}
    for job in completed:
        by_algorithm[job["algorithm"]] = job
    pid_metrics = by_algorithm.get("los_pid", {}).get("progress", {}).get("aggregate_metrics", {})
    pid_reward = float(pid_metrics.get("mean_reward", 0.0))
    ranked = sorted(
        by_algorithm.values(),
        key=lambda item: float(item["progress"].get("aggregate_metrics", {}).get("mean_reward", -1e9)),
        reverse=True,
    )
    items = []
    for index, job in enumerate(ranked):
        metrics = job["progress"].get("aggregate_metrics", {})
        reward = float(metrics.get("mean_reward", 0.0))
        congestion = 100.0 * float(metrics.get("mean_congestion", 0.0))
        conflict = 100.0 * float(metrics.get("mean_conflict_risk", 0.0))
        safety_margin = 100.0 * float(metrics.get("mean_safety_margin", 0.0))
        gain = 0.0 if job["algorithm"] == "los_pid" else reward - pid_reward
        label = ALGORITHM_LABELS[job["algorithm"]]
        items.append(
            {
                "id": f"{job['algorithm']}:{job['job_id']}",
                "title": f"{label} 留出测试策略",
                "summary": "指标来自独立测试时间段的确定性策略回放；未下发生产系统。",
                "priorityHint": "测试收益最高 · 仍需人工确认" if index == 0 else "真实测试候选 · 仍需人工确认",
                "congestionIndex": {"low": round(congestion, 2), "high": round(congestion, 2), "unit": "%"},
                "conflictRisk": {"low": round(conflict, 2), "high": round(conflict, 2), "unit": "%"},
                "safetyMargin": {"low": round(safety_margin, 2), "high": round(safety_margin, 2), "unit": "%"},
                "rewardDelta": {"low": round(gain, 3), "high": round(gain, 3), "unit": " reward", "prefix": "+" if gain >= 0 else ""},
                "effects": [
                    {"type": "system", "targetName": "held-out test split", "impact": f"mean reward={reward:.4f}; mean throughput={float(metrics.get('mean_throughput', 0.0)):.4f}", "severity": "medium"}
                ],
                "counterfactuals": [
                    {"metricName": "mean reward vs LOS-PID", "currentRange": f"{reward:.4f}", "baselineRange": f"{pid_reward:.4f}", "delta": f"{gain:+.4f}", "direction": "up" if gain >= 0 else "down"}
                ],
                "relatedAlerts": [],
                "baselinePolicyId": next((f"los_pid:{value['job_id']}" for value in ranked if value["algorithm"] == "los_pid"), None),
                "job_id": job["job_id"],
                "algorithm": job["algorithm"],
                "dataset_sha256": job["progress"].get("dataset_sha256"),
                "dataset_split": "test",
            }
        )
    return {"items": items, "source": "completed_held_out_test_artifacts", "count": len(items)}


@app.post("/api/strategy/replan")
def create_replan_review_request(payload: dict[str, Any]) -> dict[str, Any]:
    _bounded_json(payload, label="replan request")
    dataset = _dataset()
    compatible = [
        job
        for job in _completed_jobs()
        if job.get("progress", {}).get("dataset_split") == "test"
        and job.get("progress", {}).get("dataset_sha256") == dataset.dataset_sha256
    ]
    if not compatible:
        raise HTTPException(
            status_code=409,
            detail="no completed held-out test artifact matches the current dataset",
        )
    candidate = max(
        compatible,
        key=lambda item: float(
            item.get("progress", {}).get("aggregate_metrics", {}).get("mean_reward", -1e9)
        ),
    )
    request_id = f"replan-{uuid.uuid4().hex[:12]}"
    event = {
        "eventId": request_id,
        "time": utc_now(),
        "source": "human_replan_review_request",
        "source_alert_id": payload.get("source_alert_id"),
        "trigger": payload.get("trigger", "replan"),
        "candidate_job_id": candidate["job_id"],
        "candidate_algorithm": candidate["algorithm"],
        "dataset_sha256": dataset.dataset_sha256,
        "dataset_split": "test",
        "production_dispatch": False,
        "result": "review_required",
    }
    _append_audit(event)
    return {
        "accepted": True,
        "request_id": request_id,
        "status": "review_required",
        "candidate_job_id": candidate["job_id"],
        "candidate_algorithm": candidate["algorithm"],
        "dataset_sha256": dataset.dataset_sha256,
        "production_dispatch": False,
        "message": "replan review request recorded; open the strategy page for human review",
    }


@app.post("/api/control/config")
def save_advisory_control_config(payload: dict[str, Any]) -> dict[str, Any]:
    _bounded_json(payload, label="control config")
    run_mode = str(payload.get("runMode", ""))
    threshold = str(payload.get("riskThreshold", ""))
    theta = int(payload.get("theta", -1))
    window = int(payload.get("futureWindowMinutes", -1))
    if run_mode not in {"automatic", "semi_automatic", "manual_watch"}:
        raise HTTPException(status_code=422, detail="invalid runMode")
    expected_theta = {"low": 35, "medium": 60, "high": 80}.get(threshold)
    if expected_theta is None or theta != expected_theta:
        raise HTTPException(status_code=422, detail="risk threshold and theta do not match")
    if window not in {15, 30, 60}:
        raise HTTPException(status_code=422, detail="futureWindowMinutes must be 15, 30, or 60")
    config_id = f"control-{uuid.uuid4().hex[:12]}"
    record = {
        "format": "portai_advisory_control_config_v1",
        "config_id": config_id,
        "saved_at": utc_now(),
        "scope": "client_advisory_view",
        "production_applied": False,
        "config": payload,
    }
    atomic_write_json(CONTROL_CONFIG_PATH, record)
    _append_audit(
        {
            "eventId": config_id,
            "time": record["saved_at"],
            "source": "advisory_control_config",
            "scope": record["scope"],
            "production_dispatch": False,
            "payload": payload,
            "result": "recorded",
        }
    )
    return {
        "accepted": True,
        "config_id": config_id,
        "scope": record["scope"],
        "production_applied": False,
        "message": "advisory client configuration recorded; no production control changed",
    }


def _current_public_snapshot() -> dict[str, Any]:
    dataset = _dataset()
    row = dataset.test.raw_features[-1]
    timestamp = dataset.test.timestamps[-1]
    vessel_count, mean_sog, stopped, dispersion, density, spread = [float(value) for value in row]
    risk = max(0.0, min(1.0, 0.44 * density + 0.34 * stopped + 0.22 * dispersion))
    score = round(100.0 * (1.0 - risk))
    risk_score = round(100.0 * risk)
    return {
        "stabilityLevel": "critical" if risk >= 0.7 else ("watch" if risk >= 0.45 else "stable"),
        "systemScore": score,
        "strategyPressure": round(100.0 * risk),
        "constraintHeadroom": round(100.0 * (1.0 - density)),
        "riskIntervalLow": risk_score,
        "riskIntervalHigh": risk_score,
        "riskEvidence": "derived_point_from_historical_ais",
        "riskHorizonMinutes": 0,
        "trendPoints": [float(value) for value in dataset.test.raw_features[-7:, 4]],
        "summaryText": f"公开 AIS 历史回放 {timestamp.isoformat()}：船舶数 {vessel_count:.0f}，平均航速 {mean_sog:.2f} kn，位置离散 {spread:.2f} km。",
        "refreshAt": timestamp.isoformat(),
        "dataSource": "public_replay",
        "live_data_verified": False,
        "dataset_sha256": dataset.dataset_sha256,
    }


def _live_gateway_get(url: str) -> Any:
    if not url:
        raise HTTPException(status_code=503, detail="live gateway endpoint is not configured")
    headers = {"Accept": "application/json"}
    if LIVE_GATEWAY_TOKEN:
        headers["Authorization"] = f"Bearer {LIVE_GATEWAY_TOKEN}"
    try:
        response = httpx.get(url, headers=headers, timeout=5.0)
        response.raise_for_status()
        return response.json()
    except Exception as exc:
        raise HTTPException(status_code=502, detail="verified live data gateway did not respond") from exc


@app.get("/api/situation/current")
def situation_current() -> dict[str, Any]:
    if LIVE_MODE:
        if not LIVE_DATA_VERIFIED:
            raise HTTPException(status_code=503, detail="live data gateway is not verified")
        raw = _live_gateway_get(LIVE_SNAPSHOT_URL)
        if not isinstance(raw, dict):
            raise HTTPException(status_code=502, detail="live snapshot must be a JSON object")
        required = {
            "stabilityLevel",
            "systemScore",
            "strategyPressure",
            "constraintHeadroom",
            "riskIntervalLow",
            "riskIntervalHigh",
            "trendPoints",
            "summaryText",
            "refreshAt",
        }
        if not required.issubset(raw):
            raise HTTPException(status_code=502, detail="live snapshot does not satisfy the contract")
        return {**raw, "dataSource": "live", "live_data_verified": True}
    return _current_public_snapshot()


def _derived_alerts() -> list[dict[str, Any]]:
    dataset = _dataset()
    alerts: list[dict[str, Any]] = []
    for index in range(max(0, dataset.test.rows - 12), dataset.test.rows):
        row = dataset.test.raw_features[index]
        timestamp = dataset.test.timestamps[index]
        risk = float(0.44 * row[4] + 0.34 * row[2] + 0.22 * row[3])
        if risk < 0.45:
            continue
        alerts.append(
            {
                "id": f"public-replay-{dataset.dataset_sha256[:8]}-{index}",
                "title": "历史 AIS 派生交通风险指标抬升",
                "detail": f"风险指数 {risk:.3f}，船舶数 {row[0]:.0f}，停航占比 {row[2]:.3f}。仅为公开历史回放。",
                "severity": "critical" if risk >= 0.7 else "warn",
                "createdAt": timestamp.isoformat(),
                "source": "public_ais_historical_replay",
                "live_data_verified": False,
            }
        )
    return alerts[-8:]


@app.get("/api/alerts")
def alerts() -> dict[str, Any]:
    if LIVE_MODE:
        if not LIVE_DATA_VERIFIED:
            raise HTTPException(status_code=503, detail="live data gateway is not verified")
        raw = _live_gateway_get(LIVE_ALERTS_URL)
        items = raw.get("items") if isinstance(raw, dict) else raw
        if not isinstance(items, list):
            raise HTTPException(status_code=502, detail="live alerts must be a list or an items object")
        return {"items": items, "source": "verified_live_gateway", "live_data_verified": True}
    return {"items": _derived_alerts(), "source": "public_ais_historical_replay", "live_data_verified": False}


@app.websocket("/ws/alerts")
async def alerts_websocket(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        if LIVE_MODE:
            await websocket.close(code=1013)
            return
        for item in _derived_alerts():
            await websocket.send_json(item)
        while True:
            try:
                await asyncio.wait_for(websocket.receive_text(), timeout=30)
            except asyncio.TimeoutError:
                await websocket.send_json(
                    {
                        "id": f"data-heartbeat-{int(time.time())}",
                        "title": "数据源心跳",
                        "detail": "公开历史回放服务在线；不是实时港口告警。",
                        "severity": "info",
                        "createdAt": utc_now(),
                        "source": "service_health",
                    }
                )
    except WebSocketDisconnect:
        return


def _append_audit(event: Mapping[str, Any]) -> None:
    ARTIFACTS_ROOT.mkdir(parents=True, exist_ok=True)
    with _store_lock:
        previous_hash = "0" * 64
        if AUDIT_PATH.exists():
            lines = [line for line in AUDIT_PATH.read_text(encoding="utf-8").splitlines() if line]
            if lines:
                previous = json.loads(lines[-1])
                previous_hash = str(previous.get("event_hash", previous_hash))
        canonical = json.dumps(event, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        event_hash = hashlib.sha256(f"{previous_hash}:{canonical}".encode()).hexdigest()
        chained = {**event, "previous_hash": previous_hash, "event_hash": event_hash}
        with AUDIT_PATH.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(chained, ensure_ascii=False, separators=(",", ":")) + "\n")


@app.post("/audit/events")
@app.post("/api/audit/events")
def create_audit_event(payload: dict[str, Any]) -> dict[str, Any]:
    _bounded_json(payload, label="audit event")
    event = {
        **payload,
        "serverTime": utc_now(),
        "serverEventId": f"audit-{uuid.uuid4().hex[:16]}",
        "data_mode": "live" if LIVE_MODE else "public_replay",
    }
    _append_audit(event)
    return {"accepted": True, "event_id": event["serverEventId"], "server_time": event["serverTime"]}


@app.post("/api/strategy/adopt_and_label")
async def adopt_and_label(payload: dict[str, Any]) -> dict[str, Any]:
    _bounded_json(payload, label="strategy decision")
    request_id = f"decision-{uuid.uuid4().hex[:12]}"
    production_dispatch = _production_dispatch_ready()
    adapter_receipt: dict[str, Any] | None = None
    if production_dispatch:
        headers = {"Content-Type": "application/json", "Idempotency-Key": request_id}
        if EXECUTION_ADAPTER_TOKEN:
            headers["Authorization"] = f"Bearer {EXECUTION_ADAPTER_TOKEN}"
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.post(
                    EXECUTION_ADAPTER_URL,
                    json={"request_id": request_id, "decision": payload},
                    headers=headers,
                )
                response.raise_for_status()
                raw_receipt = response.json()
                adapter_receipt = raw_receipt if isinstance(raw_receipt, dict) else {"value": raw_receipt}
        except Exception as exc:
            _append_audit(
                {
                    "eventId": request_id,
                    "time": utc_now(),
                    "source": "human_strategy_decision",
                    "payload": payload,
                    "production_dispatch": False,
                    "result": "execution_adapter_failed",
                    "error_type": type(exc).__name__,
                }
            )
            raise HTTPException(status_code=502, detail="verified execution adapter did not acknowledge") from exc
    event = {
        "eventId": request_id,
        "time": utc_now(),
        "source": "human_strategy_decision",
        "payload": payload,
        "production_dispatch": production_dispatch,
        "result": "adapter_acknowledged" if production_dispatch else "recorded_dry_run_only",
        "adapter_receipt": adapter_receipt,
    }
    _append_audit(event)
    return {
        "request_id": request_id,
        "accepted": True,
        "execution_status": "acked" if production_dispatch else "dry_run_recorded",
        "production_dispatch": production_dispatch,
        "message": "verified execution adapter acknowledged the decision" if production_dispatch else "decision recorded as dry-run; production dispatch gate is closed",
    }


@app.get("/rl-panel", response_class=HTMLResponse)
def rl_panel() -> str:
    global _panel_last_seen
    _panel_last_seen = time.monotonic()
    rows = []
    for record in reversed(list(_load_requests().values())):
        request_id = html.escape(str(record["request_id"]), quote=True)
        algorithm = html.escape(
            str(record.get("config", {}).get("algorithm", "unknown")), quote=True
        )
        requested_by = html.escape(str(record.get("requested_by", "")), quote=True)
        status = html.escape(str(record.get("status", "")), quote=True)
        actions = ""
        if record.get("status") == "waiting_approval":
            actions = f"""
              <button onclick=\"approve('{request_id}')\">批准实验 / Approve</button>
              <button class=\"reject\" onclick=\"rejectReq('{request_id}')\">拒绝 / Reject</button>
            """
        rows.append(
            f"<tr><td>{request_id}</td><td>{algorithm}</td><td>{requested_by}</td><td>{status}</td><td>{actions}</td></tr>"
        )
    table_rows = "".join(rows) or '<tr><td colspan="5">暂无申请</td></tr>'
    dataset = _dataset().status()
    splits = dataset["splits"]
    evidence = html.escape(str(dataset.get("evidence_level", "unverified")), quote=True)
    mode = "verified live gateway" if LIVE_MODE and LIVE_DATA_VERIFIED else "public historical replay"
    return f"""<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"refresh\" content=\"10\"><title>PortAI Experiment Gate</title>
    <style>
    :root{{--bg:#061022;--panel:#0b1a31;--line:#203b61;--text:#eaf4ff;--muted:#90a7c3;--cyan:#52ddff;--mint:#72f2c5;--violet:#8875ff;--danger:#ff6f91}}
    *{{box-sizing:border-box}}body{{font-family:Inter,ui-sans-serif,system-ui,-apple-system,sans-serif;margin:0;min-height:100vh;background:radial-gradient(circle at 78% 0%,#17285a 0,transparent 35%),linear-gradient(145deg,#050c1c,#08172b 58%,#071123);color:var(--text)}}
    main{{max-width:1240px;margin:auto;padding:38px 28px 60px}}.eyebrow{{font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--cyan);font-weight:800}}h1{{font-size:clamp(28px,3.4vw,44px);margin:9px 0 8px;line-height:1.08;overflow-wrap:anywhere}}h1 span{{display:block;font-size:.82em;margin-top:6px}}.subtitle{{color:var(--muted);max-width:900px;line-height:1.7;margin:0 0 24px}}
    .guard{{display:flex;gap:12px;align-items:flex-start;padding:15px 17px;border:1px solid #684c8c;background:linear-gradient(90deg,#231b45aa,#131d3aaa);border-radius:16px;margin-bottom:18px}}.guard b{{color:#d4c8ff}}.dot{{width:10px;height:10px;border-radius:50%;background:var(--violet);box-shadow:0 0 18px var(--violet);margin-top:6px;flex:none}}
    .grid{{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:18px 0}}.metric{{padding:17px;border:1px solid var(--line);border-radius:16px;background:linear-gradient(145deg,#0e203aaa,#09162cdd);box-shadow:0 18px 50px #0004}}.metric span{{display:block;color:var(--muted);font-size:12px;margin-bottom:7px}}.metric strong{{font-size:18px;color:var(--mint)}}
    .flow{{border:1px solid var(--line);border-radius:18px;padding:18px;background:#08162baa;margin-bottom:18px}}.flow code{{display:block;color:var(--mint);white-space:normal;line-height:1.8;font-size:14px}}.flow small{{color:var(--muted)}}
    .table-card{{border:1px solid var(--line);border-radius:18px;background:#08162bd9;overflow:hidden}}.table-head{{display:flex;justify-content:space-between;gap:16px;align-items:center;padding:18px 20px;border-bottom:1px solid var(--line)}}.table-head h2{{margin:0;font-size:18px}}.badge{{font-size:12px;padding:6px 10px;border-radius:999px;color:var(--mint);background:#163b3d;border:1px solid #2b6b68}}table{{width:100%;border-collapse:collapse}}td,th{{padding:16px 20px;border-bottom:1px solid #173050;text-align:left;font-size:14px}}th{{color:#91a9c8;font-size:11px;text-transform:uppercase;letter-spacing:.08em}}tbody tr:hover{{background:#0d2240}}button{{padding:9px 13px;margin:3px 6px 3px 0;background:linear-gradient(100deg,#158da4,#337cbd);color:white;border:0;border-radius:9px;font-weight:750;cursor:pointer}}button:hover{{filter:brightness(1.12)}}.reject{{background:#71334b;color:#ffdce5}}footer{{margin-top:18px;color:#7089a9;font-size:12px;line-height:1.7}}
    @media(max-width:800px){{.grid{{grid-template-columns:repeat(2,minmax(0,1fr))}}.table-card{{overflow:auto}}table{{min-width:780px}}}}@media(max-width:480px){{main{{padding:24px 14px}}.grid{{grid-template-columns:1fr}}}}
    </style></head><body><main>
    <div class=\"eyebrow\">PortAI Mobile · Evidence-Gated Control Plane</div><h1>策略实验人工门禁<br><span style=\"color:var(--cyan)\">Human-Gated Policy Experiment</span></h1>
    <p class=\"subtitle\">移动端只提交数据指纹与实验参数；电脑端独立复核后才创建训练任务。训练、留出测试、回放和生产执行属于四个不同权限边界。</p>
    <div class=\"guard\"><i class=\"dot\"></i><div><b>Research boundary / 研究边界</b><br>当前来源为 {mode}；<code>production_dispatch=false</code>，界面结果不得解释为现场控制效果。</div></div>
    <section class=\"grid\"><div class=\"metric\"><span>Evidence level / 证据等级</span><strong>{evidence}</strong></div><div class=\"metric\"><span>Five-baseline contract / 五基线</span><strong>4 RL + LOS-PID</strong></div><div class=\"metric\"><span>Chronological split / 时间切分</span><strong>{splits['train']['rows']} / {splits['validation']['rows']} / {splits['test']['rows']}</strong></div><div class=\"metric\"><span>Execution authority / 执行权</span><strong>Disabled · Fail closed</strong></div></section>
    <section class=\"flow\"><small>Auditable experiment sequence / 可审计实验序列</small><code>TRAIN split · render=None → checkpoint + SHA-256 → process boundary → held-out TEST → recorded trajectory → client replay</code></section>
    <section class=\"table-card\"><div class=\"table-head\"><h2>待复核实验 / Pending experiments</h2><span class=\"badge\">Auto refresh · 10s</span></div><table><thead><tr><th>Request / 申请</th><th>Algorithm / 算法</th><th>Requester / 申请人</th><th>Status / 状态</th><th>Human gate / 人工操作</th></tr></thead><tbody>{table_rows}</tbody></table></section>
    <footer>Dataset: {html.escape(str(dataset.get('dataset_id', 'unknown')))} · SHA-256: {html.escape(str(dataset.get('dataset_sha256', ''))[:16])}…<br>Approval creates a local experiment process only. Production integration additionally requires verified live data, a verified execution adapter, authentication, site interlocks and independent acceptance.</footer>
    </main><script>async function approve(id){{await fetch(`/api/rl/train/requests/${{id}}/approve`,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{approved_by:'desktop_operator'}})}});location.reload()}}async function rejectReq(id){{await fetch(`/api/rl/train/requests/${{id}}/reject`,{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{rejected_by:'desktop_operator',reason:'operator_rejected'}})}});location.reload()}}</script></body></html>"""


def main() -> None:
    import uvicorn

    ARTIFACTS_ROOT.mkdir(parents=True, exist_ok=True)
    uvicorn.run(
        "portai_rl.api:app",
        host=SERVER_HOST,
        port=SERVER_PORT,
        reload=False,
    )


if __name__ == "__main__":
    main()
