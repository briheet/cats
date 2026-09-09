#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release
if command -v xcodegen >/dev/null; then
  xcodegen generate --spec macos/project.yml
else
  nix-shell -p xcodegen --run 'xcodegen generate --spec macos/project.yml'
fi
cats_arch="$(uname -m)"
env -u SDKROOT -u DEVELOPER_DIR -u CC -u CXX -u LD -u AR -u AS /usr/bin/xcodebuild -quiet -project macos/Cats.xcodeproj -scheme Cats -configuration Release -destination "platform=macOS,arch=$cats_arch" -derivedDataPath build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build
printf '\nBuilt: %s/build/Build/Products/Release/Cats.app\n' "$PWD"
