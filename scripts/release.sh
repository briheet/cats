#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CATS_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${CATS_TEAM_ID:?Set your Apple developer team ID}"
: "${CATS_NOTARY_PROFILE:?Set a notarytool keychain profile}"
if [[ "$CATS_SIGN_IDENTITY" != 'Developer ID Application:'* || ! "$CATS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo 'Releases require a Developer ID Application identity and a ten-character team ID.' >&2
  exit 1
fi
export CATS_APP_GROUP="$CATS_TEAM_ID.dev.cats.shared"
bash scripts/build.sh
cats_bundle=build/Build/Products/Release/Cats.app
cats_team="$(/usr/bin/codesign -dv "$cats_bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
test "$cats_team" = "$CATS_TEAM_ID"
cats_arch="$(uname -m)"
cats_archive="$PWD/build/Cats-$cats_arch.zip"
/usr/bin/ditto -c -k --keepParent "$cats_bundle" "$cats_archive"
/usr/bin/xcrun notarytool submit "$cats_archive" --keychain-profile "$CATS_NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$cats_bundle"
/usr/bin/xcrun stapler validate "$cats_bundle"
/usr/sbin/spctl --assess --type execute --verbose "$cats_bundle"
/usr/bin/ditto -c -k --keepParent "$cats_bundle" "$cats_archive"
echo "Notarized release: $cats_archive"
