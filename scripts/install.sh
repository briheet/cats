#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
destination="${CATS_INSTALL_DIR:-$HOME/Applications}/Cats.app"
bash scripts/install-bundle.sh "$PWD/build/Build/Products/Release/Cats.app" "$destination"
open -gj "$destination"
