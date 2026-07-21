#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python_bin="${PORTAI_PYTHON:-python3}"

cd "$project_dir"
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

if git ls-files | rg '(^|/)(\.env$|\.dart_tool/|build/|\.idea/|\.venv/|artifacts/|__pycache__/|\.pytest_cache/)|local\.properties$'; then
  echo "release check failed: local or generated artifact is tracked" >&2
  exit 1
fi

if git grep -n -E '/Users/|/var/folders/|BEGIN (RSA|OPENSSH|EC) PRIVATE|github_pat_|ghp_[A-Za-z0-9]+' -- ':!pubspec.lock' ':!scripts/release_check.sh'; then
  echo "release check failed: workstation path or credential marker found" >&2
  exit 1
fi

echo "release check passed"
