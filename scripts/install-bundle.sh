#!/bin/bash
set -euo pipefail
source_bundle="${1:?Pass a Cats product app bundle}"
destination="${2:?Pass an absolute app destination}"
display="$(basename "$source_bundle" .app)"
case "$display" in
  CatsLLM) identifier=dev.cats.llm ;;
  CatsMetrics) identifier=dev.cats.metrics ;;
  *) echo 'Not a Cats product bundle' >&2; exit 2 ;;
esac
[[ "$destination" == /*/"$display.app" ]] || { echo 'Destination must be absolute and match the product' >&2; exit 2; }
test -x "$source_bundle/Contents/MacOS/$display"
test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$source_bundle/Contents/Info.plist")" = "$identifier"
parent="$(dirname "$destination")"
mkdir -p "$parent"
receipt="$parent/.$display-installed-source"
if [[ -e "$destination" || -L "$destination" ]]; then
  [[ -f "$receipt" ]] || { echo 'Unmanaged app exists; move it aside before installing.' >&2; exit 1; }
  test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist")" = "$identifier"
  if [[ "$(<"$receipt")" == "$source_bundle" ]] && diff -qr "$source_bundle" "$destination" > /dev/null; then exit 0; fi
fi
stage="$(mktemp -d "$parent/.$display-install.XXXXXX")"
/usr/bin/ditto "$source_bundle" "$stage/$display.app"
chmod -R u+w "$stage/$display.app"
if [[ -e "$destination" || -L "$destination" ]]; then
  mv "$destination" "$stage/previous-bundle"
  echo "Previous bundle preserved at $stage/previous-bundle"
fi
mv "$stage/$display.app" "$destination"
rmdir "$stage" 2>/dev/null || true
printf '%s\n' "$source_bundle" > "$receipt"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
