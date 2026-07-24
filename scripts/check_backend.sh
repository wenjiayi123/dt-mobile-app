#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python_bin="${PORTAI_PYTHON:-python3}"

cd "$project_dir"
PYTHONPATH="$project_dir/backend${PYTHONPATH:+:$PYTHONPATH}" \
  "$python_bin" -m py_compile backend/portai_rl/*.py scripts/*.py
PYTHONPATH="$project_dir/backend${PYTHONPATH:+:$PYTHONPATH}" \
  "$python_bin" -m pytest backend/tests
