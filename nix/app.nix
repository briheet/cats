{
  lib,
  stdenvNoCC,
  src,
}:
# Import an existing Xcode-built bundle without changing its signed contents.
stdenvNoCC.mkDerivation {
  pname = "cats-app";
  version = "0.1.0";
  inherit src;
  dontUnpack = true;
  dontFixup = true;
  installPhase = ''
    test -f "$src/Contents/Info.plist"
    test -x "$src/Contents/MacOS/Cats"
    mkdir -p "$out/Applications/Cats.app"
    cp -R "$src/." "$out/Applications/Cats.app/"
  '';
  meta.platforms = lib.platforms.darwin;
}
