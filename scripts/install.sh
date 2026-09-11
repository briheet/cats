#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
product="${1:?Pass llm or metrics}"
case "$product" in
  llm) display=CatsLLM ;;
  metrics) display=CatsMetrics ;;
  *) echo 'Usage: install.sh llm|metrics' >&2; exit 2 ;;
esac
bash scripts/build.sh "$product"
destination="${2:-$HOME/Applications}/$display.app"
bash scripts/install-bundle.sh "$PWD/build/Build/Products/Release/$display.app" "$destination"
open -gj "$destination"
