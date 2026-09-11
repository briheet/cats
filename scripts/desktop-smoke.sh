#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cats_executable="${1:-$PWD/build/Build/Products/Release/CatsLLM.app/Contents/MacOS/CatsLLM}"
cats_scratch="$(mktemp -d)"
printf 'Test logs: %s\n' "$cats_scratch/ui.log"
cp macos/Tests/Fixtures/state.json "$cats_scratch/state.json"
# Isolate all telemetry and suppress collection. Never open real user sources.
CATS_LLM_DATA_DIR="$cats_scratch" CATS_LLM_EXTERNAL_COLLECTOR=1 "$cats_executable" > "$cats_scratch/ui.log" 2>&1 &
cats_test_pid=$!
trap 'kill -TERM "$cats_test_pid" 2>/dev/null || true; wait "$cats_test_pid" 2>/dev/null || true' EXIT
sleep 3
kill -0 "$cats_test_pid"
cat "$cats_scratch/ui.log"
env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swift scripts/desktop-smoke.swift "$cats_test_pid"
printf 'Test logs retained at %s\n' "$cats_scratch"
