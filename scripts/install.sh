#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
destination="${CATS_INSTALL_DIR:-$HOME/Applications}/Cats.app"
if [ -e "$destination" ]; then
  printf 'Existing app at %s. Move it aside before installing.\n' "$destination" >&2
  exit 1
fi
mkdir -p "$(dirname "$destination")"
ditto build/Build/Products/Release/Cats.app "$destination"
codesign --force --deep --sign - "$destination"
open "$destination"
