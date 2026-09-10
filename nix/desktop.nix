{
  lib,
  stdenv,
  swift,
  apple-sdk,
  cats,
  makeWrapper,
}:
stdenv.mkDerivation {
  pname = "cats-desktop";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../macos/CatsApp
      ../macos/Shared
      ../macos/Views
    ];
  };
  nativeBuildInputs = [
    swift
    makeWrapper
  ];
  buildInputs = [ apple-sdk ];
  buildPhase = ''
    runHook preBuild
    swiftc -O -parse-as-library -module-cache-path "$TMPDIR/swift-cache" \
      -target ${if stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64"}-apple-macos14.0 \
      macos/CatsApp/*.swift \
      macos/Shared/*.swift macos/Views/*.swift \
      -o cats-desktop
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec"
    cp cats-desktop "$out/libexec/cats-desktop"
    makeWrapper "$out/libexec/cats-desktop" "$out/bin/cats-desktop" \
      --set-default CATS_COLLECTOR ${lib.getExe cats}
    runHook postInstall
  '';
  passthru.collector = cats;
  meta = {
    description = "Cats native glass desktop panels (no Apple account required)";
    mainProgram = "cats-desktop";
    platforms = lib.platforms.darwin;
  };
}
