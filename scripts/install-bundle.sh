#!/bin/bash
set -euo pipefail
cats_source="${1:?Pass a Cats.app bundle}"
cats_destination="${2:?Pass an absolute installation path ending in Cats.app}"
if [[ "$cats_destination" != /*/Cats.app ]]; then
  echo 'Destination must be an absolute Cats.app path' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$cats_source"
test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$cats_source/Contents/Info.plist")" = dev.cats.app
test -x "$cats_source/Contents/PlugIns/CatsWidget.appex/Contents/MacOS/CatsWidget"
cats_parent="$(dirname "$cats_destination")"
mkdir -p "$cats_parent"
cats_receipt="$cats_parent/.cats-installed-source"
if [[ -e "$cats_destination" || -L "$cats_destination" ]]; then
  if [[ ! -f "$cats_receipt" ]]; then
    echo "Unmanaged app exists at $cats_destination; move it aside before installing." >&2
    exit 1
  fi
  test "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$cats_destination/Contents/Info.plist")" = dev.cats.app
  if [[ "$(<"$cats_receipt")" == "$cats_source" ]] && diff -qr "$cats_source" "$cats_destination" > /dev/null; then
    /usr/bin/codesign --verify --deep --strict "$cats_destination"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$cats_destination"
    exit 0
  fi
fi
cats_stage="$(mktemp -d "$cats_parent/.cats-install.XXXXXX")"
/usr/bin/ditto "$cats_source" "$cats_stage/Cats.app"
/usr/bin/codesign --verify --deep --strict "$cats_stage/Cats.app"
if [[ -e "$cats_destination" || -L "$cats_destination" ]]; then
  mv "$cats_destination" "$cats_stage/previous-bundle"
  echo "Previous Cats bundle preserved at $cats_stage/previous-bundle"
fi
mv "$cats_stage/Cats.app" "$cats_destination"
rmdir "$cats_stage" 2>/dev/null || true # Keep previous-bundle backups.
printf '%s\n' "$cats_source" > "$cats_receipt"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$cats_destination"
