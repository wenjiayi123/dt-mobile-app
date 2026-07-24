#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${PORTAI_PYTHON:-}" ]]; then
  python_bin="$PORTAI_PYTHON"
elif [[ -x "$project_dir/backend/.venv/bin/python" ]]; then
  python_bin="$project_dir/backend/.venv/bin/python"
elif [[ -x "$project_dir/.venv/bin/python" ]]; then
  python_bin="$project_dir/.venv/bin/python"
else
  python_bin="$(command -v python3 || true)"
fi

cd "$project_dir"
if [[ -z "$python_bin" ]] || ! "$python_bin" -c 'import gymnasium, numpy, pytest, stable_baselines3' >/dev/null 2>&1; then
  cat >&2 <<'EOF'
release check failed: the isolated Python verification environment is missing.
Create it with:
  python3.12 -m venv backend/.venv
  backend/.venv/bin/python -m pip install -r backend/requirements.txt
Then rerun:
  bash scripts/release_check.sh
EOF
  exit 1
fi
export PORTAI_PYTHON="$python_bin"

for required_doc in \
  docs/SHARED_BACKEND_CONTRACT.md \
  docs/EVIDENCE_INDEX.md \
  docs/RESUME_CLAIMS_DUAL_FRONTEND.md; do
  if [[ ! -f "$required_doc" ]]; then
    echo "release check failed: missing dual-frontend evidence: $required_doc" >&2
    exit 1
  fi
done

for required_font_asset in \
  assets/fonts/PortAISansSC.ttf \
  assets/fonts/OFL.txt; do
  if [[ ! -s "$required_font_asset" ]]; then
    echo "release check failed: missing bundled Chinese font asset: $required_font_asset" >&2
    exit 1
  fi
done

if ! rg -q "family: PortAISansSC" pubspec.yaml ||
   ! rg -q "fontFamily: 'PortAISansSC'" lib/app.dart; then
  echo "release check failed: bundled Chinese font is not wired into the app theme" >&2
  exit 1
fi
"$python_bin" - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, str(Path.cwd() / "backend"))
from portai_rl.contracts import ALGORITHM_IDS, load_dataset

assert ALGORITHM_IDS == ("ppo", "sac", "td3", "dqn", "los_pid")
dataset = load_dataset("backend/config/public_noaa_ais.json")
assert dataset.train.timestamps[-1] < dataset.validation.timestamps[0]
assert dataset.validation.timestamps[-1] < dataset.test.timestamps[0]
assert dataset.manifest["live_data_verified"] is False
print(dataset.status())
PY

bash scripts/check_backend.sh
bash scripts/check.sh
"$python_bin" scripts/smoke_all_baselines.py --timesteps 128 --output "${TMPDIR:-/tmp}/portai-release-smoke"

for contract_marker in \
  "/api/mobile/status" \
  "/api/mobile/situation" \
  "/api/mobile/strategy/candidates" \
  "/api/mobile/strategy/decisions" \
  "/api/mobile/audit/events"; do
  if ! rg -q "$contract_marker" lib; then
    echo "release check failed: shared backend marker missing: $contract_marker" >&2
    exit 1
  fi
done

if rg -n "LOS-PID|los_pid" lib; then
  echo "release check failed: Flutter UI still exposes the standalone AIS control contract" >&2
  exit 1
fi

if rg -n "xiaoyi_sprite|mockFallback|LOCAL-B03-FALLBACK|LOCAL-B03-DETERMINISTIC" lib pubspec.yaml; then
  echo "release check failed: display-only fallback marker found" >&2
  exit 1
fi

if rg -n '"delayRisk"|"kpiDelta"' backend/portai_rl/api.py; then
  echo "release check failed: obsolete fabricated strategy metric contract found" >&2
  exit 1
fi

if rg -n "未来 15 min 风险区间|StrategyCandidatesDataSource\.live|SystemPushNotificationService" lib; then
  echo "release check failed: misleading future/live/no-op module marker found" >&2
  exit 1
fi

if ! rg -q "等待接入港口" lib/features/home lib/features/situation; then
  echo "release check failed: first-clone port-integration boundary is not visible" >&2
  exit 1
fi

if ! rg -q "production_dispatch.*!= false|production_dispatch.*== false" \
  lib/features/strategy/application/strategy_controller.dart; then
  echo "release check failed: mobile dry-run receipt is not fail-closed" >&2
  exit 1
fi

if git ls-files | rg '(^|/)(\.env$|\.dart_tool/|build/|\.idea/|\.venv/|artifacts/|__pycache__/|\.pytest_cache/)|local\.properties$'; then
  echo "release check failed: local or generated artifact is tracked" >&2
  exit 1
fi

if git grep -n -E '/Users/|/var/folders/|BEGIN (RSA|OPENSSH|EC) PRIVATE|github_pat_|ghp_[A-Za-z0-9]+' -- ':!pubspec.lock' ':!scripts/release_check.sh'; then
  echo "release check failed: workstation path or credential marker found" >&2
  exit 1
fi

echo "release check passed"
