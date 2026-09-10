#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release
# swiftc supplies the required ARM64 ad-hoc signature; no account or certificate.
cats_bundle=build/Build/Products/Release/Cats.app
if [[ -d "$cats_bundle" ]]; then
  cats_backup="$(mktemp -d build/previous-app.XXXXXX)"
  mv "$cats_bundle" "$cats_backup/Cats.app"
fi
mkdir -p "$cats_bundle/Contents/MacOS" "$cats_bundle/Contents/Helpers"
cats_arch="$(uname -m)"
env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swiftc -O -parse-as-library \
  -target "$cats_arch-apple-macos14.0" \
  macos/CatsApp/*.swift \
  macos/Shared/*.swift macos/Views/*.swift \
  -o "$cats_bundle/Contents/MacOS/Cats"
cp macos/CatsApp/Info.plist "$cats_bundle/Contents/Info.plist"
cp target/release/cats "$cats_bundle/Contents/Helpers/cats"
printf '\nBuilt: %s/%s\n' "$PWD" "$cats_bundle"
