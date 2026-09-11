{
  lib,
  rustPlatform,
  product,
}:
rustPlatform.buildRustPackage {
  pname = "cats-${product}";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
      ../themes
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;
  cargoBuildFlags = [
    "-p"
    "cats-${product}"
  ];
  cargoTestFlags = [
    "-p"
    "cats-${product}"
  ];
  meta = {
    description = "Cats ${product} collector";
    mainProgram = "cats-${product}";
    platforms = lib.platforms.darwin;
  };
}
