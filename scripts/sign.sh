#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cats_bundle="${1:?Pass the built Cats.app path}"
cats_identity="${CATS_SIGN_IDENTITY:--}"
cats_group="${CATS_APP_GROUP:-group.dev.cats.shared}"
if [[ ! "$cats_group" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+$ ]]; then
  echo 'Invalid CATS_APP_GROUP' >&2
  exit 1
fi
mkdir -p build/signing
# Expand the same build setting used in the app and widget Info.plists.
sed "s/\$(CATS_APP_GROUP)/$cats_group/g" macos/CatsApp/Cats.entitlements > build/signing/app.plist
sed "s/\$(CATS_APP_GROUP)/$cats_group/g" macos/CatsWidget/CatsWidget.entitlements > build/signing/widget.plist
cats_flags=(--force --sign "$cats_identity")
if [[ "$cats_identity" != - ]]; then
  cats_flags+=(--timestamp --options runtime)
else
  echo 'Development signing only: this bundle is not a distributable WidgetKit release.' >&2
fi
/usr/bin/codesign "${cats_flags[@]}" --entitlements build/signing/app.plist "$cats_bundle/Contents/Helpers/cats"
/usr/bin/codesign "${cats_flags[@]}" --entitlements build/signing/widget.plist "$cats_bundle/Contents/PlugIns/CatsWidget.appex"
/usr/bin/codesign "${cats_flags[@]}" --entitlements build/signing/app.plist "$cats_bundle"
/usr/bin/codesign --verify --deep --strict "$cats_bundle"
