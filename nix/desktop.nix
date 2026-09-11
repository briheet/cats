{
  lib,
  stdenv,
  swift,
  apple-sdk,
  makeWrapper,
  product,
  collector,
}:
let
  metrics = product == "metrics";
  prefix = if metrics then "CATS_METRICS" else "CATS_LLM";
in
stdenv.mkDerivation {
  pname = "cats-${product}-desktop";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions (
      [ ../macos/UI ]
      ++ (
        if metrics then
          [
            ../macos/MetricsApp
            ../macos/MetricsShared
          ]
        else
          [
            ../macos/CatsApp
            ../macos/Shared
            ../macos/Views
          ]
      )
    );
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
      ${
        if metrics then
          "-D METRICS macos/MetricsApp/*.swift macos/MetricsShared/*.swift"
        else
          "macos/CatsApp/*.swift macos/Shared/*.swift macos/Views/*.swift"
      } \
      macos/UI/*.swift -o cats-${product}-desktop
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec"
    cp cats-${product}-desktop "$out/libexec/"
    makeWrapper "$out/libexec/cats-${product}-desktop" "$out/bin/cats-${product}-desktop" \
      --set-default ${prefix}_COLLECTOR ${lib.getExe collector}
    runHook postInstall
  '';
  passthru = { inherit collector; };
  meta = {
    description = "Cats ${product} native desktop panels and menu bar";
    mainProgram = "cats-${product}-desktop";
    platforms = lib.platforms.darwin;
  };
}
