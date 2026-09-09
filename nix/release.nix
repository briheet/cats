{ pkgs }:
let
  releases = builtins.fromJSON (builtins.readFile ./releases.json);
  release = releases.${pkgs.stdenv.hostPlatform.system} or null;
in
if release == null then
  null
else
  pkgs.callPackage ./app.nix {
    appGroup = release.appGroup;
    src =
      pkgs.runCommand "cats-release-${release.version}"
        {
          nativeBuildInputs = [ pkgs.unzip ];
          archive = pkgs.fetchurl { inherit (release) url hash; };
        }
        ''
          unzip -q "$archive"
          mv Cats.app "$out"
        '';
  }
