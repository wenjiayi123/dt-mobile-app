#!/usr/bin/env bash
set -euo pipefail

echo "==> dart format ."
dart format .

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

echo "✅ quality check passed"
