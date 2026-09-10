#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cats_mode="${1:-check}"
case "$cats_mode" in
  check|format) ;;
  *) echo 'Usage: format-swift.sh [check|format]' >&2; exit 2 ;;
esac
if ! command -v swift-format >/dev/null; then
  exec nix-shell -p swift-format --run "bash scripts/format-swift.sh $cats_mode"
fi
cats_sources=(macos/CatsApp macos/Shared macos/Views macos/Preview macos/Tests macos/Package.swift scripts/*.swift)
if [[ "$cats_mode" == format ]]; then
  swift-format format --in-place --recursive "${cats_sources[@]}"
else
  swift-format lint --strict --recursive "${cats_sources[@]}"
fi
