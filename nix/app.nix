{
  lib,
  stdenvNoCC,
  src,
  appGroup ? "group.dev.cats.shared",
}:
# Import an existing Xcode-built bundle without changing its signed contents.
stdenvNoCC.mkDerivation {
  pname = "cats-app";
  version = "0.1.0";
  inherit src;
  dontUnpack = true;
  dontFixup = true;
  passthru = { inherit appGroup; };
  installPhase = ''
    test -f "$src/Contents/Info.plist"
    test -x "$src/Contents/MacOS/Cats"
    test -x "$src/Contents/PlugIns/CatsWidget.appex/Contents/MacOS/CatsWidget"
    mkdir -p "$out/Applications/Cats.app"
    cp -R "$src/." "$out/Applications/Cats.app/"
  '';
  meta.platforms = lib.platforms.darwin;
}
