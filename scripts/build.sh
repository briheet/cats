#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
products=("${@:-llm metrics}")
if [[ $# == 0 ]]; then products=(llm metrics); fi
for product in "${products[@]}"; do
  case "$product" in
    llm) display=CatsLLM; sources=(macos/CatsApp/*.swift macos/Shared/*.swift macos/Views/*.swift); flags=() ;;
    metrics) display=CatsMetrics; sources=(macos/MetricsApp/*.swift macos/MetricsShared/*.swift); flags=(-D METRICS) ;;
    *) echo 'Usage: build.sh [llm|metrics ...]' >&2; exit 2 ;;
  esac
  cargo build --release -p "cats-$product"
  bundle="build/Build/Products/Release/$display.app"
  if [[ -d "$bundle" ]]; then
    backup="$(mktemp -d build/previous-app.XXXXXX)"
    mv "$bundle" "$backup/$display.app"
  fi
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Helpers"
  env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -O -parse-as-library \
    -target "$(uname -m)-apple-macos14.0" "${flags[@]}" \
    "${sources[@]}" macos/UI/*.swift -o "$bundle/Contents/MacOS/$display"
  cp "macos/$(if [[ $product == llm ]]; then echo CatsApp; else echo MetricsApp; fi)/Info.plist" "$bundle/Contents/Info.plist"
  cp "target/release/cats-$product" "$bundle/Contents/Helpers/cats-$product"
  printf 'Built: %s\n' "$bundle"
done
