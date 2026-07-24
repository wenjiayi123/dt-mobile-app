from __future__ import annotations

import json
from pathlib import Path

from fastapi.testclient import TestClient

from portai_rl import api
from test_contracts import make_manifest


def configure_api(tmp_path: Path, monkeypatch) -> TestClient:
    artifacts = tmp_path / "artifacts"
    monkeypatch.setattr(api, "ARTIFACTS_ROOT", artifacts)
    monkeypatch.setattr(api, "REQUESTS_PATH", artifacts / "requests.json")
    monkeypatch.setattr(api, "AUDIT_PATH", artifacts / "audit_events.jsonl")
    monkeypatch.setattr(api, "CONTROL_CONFIG_PATH", artifacts / "control_config.json")
    monkeypatch.setattr(api, "MANIFEST_PATH", make_manifest(tmp_path, rows=120))
    monkeypatch.setattr(api, "LIVE_MODE", False)
    monkeypatch.setattr(api, "LIVE_DATA_VERIFIED", False)
    monkeypatch.setattr(api, "EXECUTION_ADAPTER_VERIFIED", False)
    monkeypatch.setattr(api, "EXECUTION_ADAPTER_URL", "")
    monkeypatch.setattr(api, "API_KEY", "")
    return TestClient(api.app)


def test_baselines_and_dataset_contract(tmp_path: Path, monkeypatch) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.get("/api/rl/train/baselines")
    assert response.status_code == 200
    body = response.json()
    assert body["contract"] == "four_rl_plus_one_control"
    assert [item["id"] for item in body["items"]] == [
        "ppo",
        "sac",
        "td3",
        "dqn",
        "los_pid",
    ]
    assert body["training_render_mode"] is None
    assert body["evaluation_render_mode"] == "recorded_test_trajectory"

    situation = client.get("/api/situation/current").json()
    assert situation["dataSource"] == "public_replay"
    assert situation["riskIntervalLow"] == situation["riskIntervalHigh"]
    assert situation["riskEvidence"] == "derived_point_from_historical_ais"
    assert situation["riskHorizonMinutes"] == 0


def test_flutter_web_cors_preflight_allows_client_headers(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.options(
        "/api/data/status",
        headers={
            "Origin": "http://127.0.0.1:8765",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": (
                "content-type,x-client-app,x-client-mode,x-client-platform,x-app-env"
            ),
        },
    )
    assert response.status_code == 200
    assert "x-client-platform" in response.headers["access-control-allow-headers"].lower()


def test_training_request_rejects_stale_dataset_hash(tmp_path: Path, monkeypatch) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.post(
        "/api/rl/train/requests",
        json={
            "config": {
                "algorithm": "ppo",
                "total_steps": 128,
                "dataset_sha256": "0" * 64,
            }
        },
    )
    assert response.status_code == 409


def test_training_request_rejects_unbounded_or_invalid_parameters(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.post(
        "/api/rl/train/requests",
        json={"config": {"algorithm": "ppo", "total_steps": "not-a-number"}},
    )
    assert response.status_code == 422
    response = client.post(
        "/api/rl/train/requests",
        json={"config": {"algorithm": "los_pid", "total_steps": 31}},
    )
    assert response.status_code == 422


def test_job_identifiers_cannot_escape_artifact_root(tmp_path: Path, monkeypatch) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.get("/api/rl/train/status", params={"job_id": "../../etc"})
    assert response.status_code == 422


def test_requester_cannot_approve_own_training_request(tmp_path: Path, monkeypatch) -> None:
    client = configure_api(tmp_path, monkeypatch)
    created = client.post(
        "/api/rl/train/requests",
        json={
            "requested_by": "same-operator",
            "config": {"algorithm": "ppo", "total_steps": 64},
        },
    )
    request_id = created.json()["request_id"]
    approved = client.post(
        f"/api/rl/train/requests/{request_id}/approve",
        json={"approved_by": "same-operator"},
    )
    assert approved.status_code == 409
    assert "different" in approved.json()["detail"]


def test_optional_api_key_protects_all_non_health_http_routes(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    monkeypatch.setattr(api, "API_KEY", "a" * 32)
    assert client.get("/health").status_code == 200
    assert client.get("/api/data/status").status_code == 401
    response = client.get(
        "/api/data/status",
        headers={"Authorization": f"Bearer {'a' * 32}"},
    )
    assert response.status_code == 200


def test_approval_panel_escapes_request_metadata(tmp_path: Path, monkeypatch) -> None:
    client = configure_api(tmp_path, monkeypatch)
    created = client.post(
        "/api/rl/train/requests",
        json={
            "requested_by": "<script>alert(1)</script>",
            "config": {"algorithm": "ppo", "total_steps": 64},
        },
    )
    assert created.status_code == 200
    panel = client.get("/rl-panel")
    assert panel.status_code == 200
    assert "<script>alert(1)</script>" not in panel.text
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in panel.text


def test_public_replay_decision_is_dry_run_and_audit_is_chained(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    decision = client.post(
        "/api/strategy/adopt_and_label",
        json={"policy_id": "ppo:test", "action_type": "guidance"},
    )
    assert decision.status_code == 200
    assert decision.json()["production_dispatch"] is False
    assert decision.json()["execution_status"] == "dry_run_recorded"

    event = client.post("/api/audit/events", json={"eventId": "second"})
    assert event.status_code == 200
    records = [json.loads(line) for line in api.AUDIT_PATH.read_text().splitlines()]
    assert len(records) == 2
    assert records[0]["previous_hash"] == "0" * 64
    assert records[1]["previous_hash"] == records[0]["event_hash"]
    assert len(records[1]["event_hash"]) == 64


def test_replan_review_requires_matching_completed_test_artifact(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    missing = client.post("/api/strategy/replan", json={"trigger": "replan"})
    assert missing.status_code == 409

    dataset_sha = api._dataset().dataset_sha256
    job_id = "job-a1b2c3d4e5f6"
    job_dir = api.ARTIFACTS_ROOT / job_id
    job_dir.mkdir(parents=True)
    progress = job_dir / "progress.json"
    progress.write_text(
        json.dumps(
            {
                "status": "COMPLETED",
                "dataset_split": "test",
                "dataset_sha256": dataset_sha,
                "aggregate_metrics": {"mean_reward": 1.5},
            }
        )
    )
    (job_dir / "job.json").write_text(
        json.dumps(
            {
                "job_id": job_id,
                "algorithm": "ppo",
                "progress_path": str(progress),
            }
        )
    )
    response = client.post(
        "/api/strategy/replan",
        json={"trigger": "replan", "source_alert_id": "alert-1"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["accepted"] is True
    assert body["status"] == "review_required"
    assert body["candidate_job_id"] == job_id
    assert body["production_dispatch"] is False


def test_control_config_is_recorded_as_advisory_not_production(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    response = client.post(
        "/api/control/config",
        json={
            "runMode": "semi_automatic",
            "riskThreshold": "medium",
            "theta": 60,
            "futureWindowMinutes": 30,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["scope"] == "client_advisory_view"
    assert body["production_applied"] is False
    saved = json.loads(api.CONTROL_CONFIG_PATH.read_text())
    assert saved["config"]["theta"] == 60


def test_strategy_candidate_exposes_exact_test_metrics_without_fake_ranges(
    tmp_path: Path, monkeypatch
) -> None:
    client = configure_api(tmp_path, monkeypatch)
    job_id = "job-0a1b2c3d4e5f"
    job_dir = api.ARTIFACTS_ROOT / job_id
    job_dir.mkdir(parents=True)
    progress = job_dir / "progress.json"
    progress.write_text(
        json.dumps(
            {
                "status": "COMPLETED",
                "dataset_split": "test",
                "aggregate_metrics": {
                    "mean_reward": 1.25,
                    "mean_throughput": 0.61,
                    "mean_congestion": 0.23,
                    "mean_conflict_risk": 0.17,
                    "mean_safety_margin": 0.83,
                },
            }
        )
    )
    (job_dir / "job.json").write_text(
        json.dumps(
            {
                "job_id": job_id,
                "algorithm": "ppo",
                "progress_path": str(progress),
            }
        )
    )

    response = client.get("/api/strategy/candidates")
    assert response.status_code == 200
    candidate = response.json()["items"][0]
    assert candidate["congestionIndex"]["low"] == 23.0
    assert candidate["congestionIndex"]["high"] == 23.0
    assert candidate["conflictRisk"]["low"] == 17.0
    assert candidate["safetyMargin"]["low"] == 83.0
    assert "delayRisk" not in candidate
    assert "kpiDelta" not in candidate
