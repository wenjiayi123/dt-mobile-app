#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/managed-runtime-build.XXXXXX")"
trap 'rm -rf -- "$TEST_BUILD_DIR"' EXIT

xcrun swiftc -parse-as-library \
  "$TEST_DIR/../ManagedProcessRuntime.swift" \
  "$TEST_DIR/../ApplicationFreshness.swift" \
  "$TEST_DIR/ManagedProcessRuntimeTests.swift" \
  -o "$TEST_BUILD_DIR/ManagedProcessRuntimeTests"
"$TEST_BUILD_DIR/ManagedProcessRuntimeTests"
