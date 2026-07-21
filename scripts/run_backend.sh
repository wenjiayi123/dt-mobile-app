#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
venv_dir="$project_dir/.venv"
python_bootstrap="${PORTAI_BOOTSTRAP_PYTHON:-}"

if [ -z "$python_bootstrap" ]; then
  if command -v python3.12 >/dev/null 2>&1; then
    python_bootstrap="python3.12"
  else
    python_bootstrap="python3"
  fi
fi

"$python_bootstrap" - <<'PY'
import sys
if not ((3, 12) <= sys.version_info[:2] < (3, 15)):
    raise SystemExit("PortAI backend requires Python 3.12, 3.13, or 3.14")
PY

if [ ! -x "$venv_dir/bin/python" ]; then
  "$python_bootstrap" -m venv "$venv_dir"
  "$venv_dir/bin/python" -m pip install --upgrade pip
  "$venv_dir/bin/python" -m pip install --requirement "$project_dir/backend/requirements.txt"
fi

cd "$project_dir/backend"
umask 077
exec "$venv_dir/bin/python" -m portai_rl.api
