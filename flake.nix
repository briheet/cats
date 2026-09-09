{
  description = "Cats — native glass widgets and local AI telemetry";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          cats = pkgs.callPackage ./nix/package.nix { };
          default = self.packages.${system}.cats;
        }
      );
      overlays.default = final: _: { cats = final.callPackage ./nix/package.nix { }; };
      homeManagerModules.default = import ./nix/home-manager.nix;
      homeManagerModules.cats = self.homeManagerModules.default;
      lib.mkApp = { pkgs, src }: pkgs.callPackage ./nix/app.nix { inherit src; };
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.cats}/bin/cats";
        };
      });
      devShells = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              cargo
              rustc
              rustfmt
              clippy
              just
              xcodegen
              nixfmt
            ];
          };
        }
      );
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          home = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home.username = "cats-test";
                home.homeDirectory = "/Users/cats-test";
                home.stateVersion = "25.11";
                programs.cats = {
                  enable = true;
                  service.enable = true;
                  settings = {
                    budget-usd = 30;
                    theme = "custom";
                  };
                  themes.custom = {
                    inherits = "nord";
                    colors.accent = "#88c0d0";
                  };
                };
              }
            ];
          };
        in
        {
          collector = self.packages.${system}.cats;
          home-manager = pkgs.runCommand "cats-home-manager-check" { } ''
            mkdir -p config/themes
            cp ${home.config.xdg.configFile."cats/config.toml".source} config/config.toml
            cp ${home.config.xdg.configFile."cats/themes/custom.toml".source} config/themes/custom.toml
            HOME="$TMPDIR" ${self.packages.${system}.cats}/bin/cats --config "$PWD/config/config.toml" config > "$out"
            test -f ${home.activationPackage}/LaunchAgents/org.nix-community.home.cats.plist
          '';
        }
      );
    };
}
