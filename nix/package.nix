{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "cats";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../rust
      ../themes
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;
  meta = {
    description = "Local AI-agent telemetry collector for Cats";
    mainProgram = "cats";
    platforms = lib.platforms.darwin;
  };
}
