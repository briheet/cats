{
  description = "Cats — independent native LLM and system telemetry";
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
      ]
      ++ nixpkgs.lib.optional (nixpkgs.lib.versionOlder (nixpkgs.lib.versions.majorMinor nixpkgs.lib.version) "26.11") "x86_64-darwin";
      eachSystem = nixpkgs.lib.genAttrs systems;
      products = [
        "llm"
        "metrics"
      ];
      packagesFor =
        pkgs:
        builtins.listToAttrs (
          nixpkgs.lib.concatMap (
            product:
            let
              collector = pkgs.callPackage ./nix/package.nix { inherit product; };
            in
            [
              {
                name = "cats-${product}";
                value = collector;
              }
              {
                name = "cats-${product}-desktop";
                value = pkgs.callPackage ./nix/desktop.nix { inherit product collector; };
              }
            ]
          ) products
        );
    in
    {
      packages = eachSystem (system: packagesFor nixpkgs.legacyPackages.${system});
      overlays.default = final: _: packagesFor final;
      homeManagerModules = {
        default = import ./nix/home-manager.nix;
        cats-llm = import ./nix/product-module.nix "llm";
        cats-metrics = import ./nix/product-module.nix "metrics";
      };
      apps = eachSystem (
        system:
        nixpkgs.lib.mapAttrs (name: package: {
          type = "app";
          program = nixpkgs.lib.getExe package;
        }) self.packages.${system}
      );
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
              nixfmt
              swift-format
            ];
          };
        }
      );
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          makeHome =
            programs:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.homeManagerModules.default
                {
                  home.username = "cats-test";
                  home.homeDirectory = "/Users/cats-test";
                  home.stateVersion = "25.11";
                  inherit programs;
                }
              ];
            };
          both = makeHome {
            cats-llm.enable = true;
            cats-metrics = {
              enable = true;
              settings.theme = "custom";
              themes.custom = {
                inherits = "nord";
                colors.accent = "#88c0d0";
              };
            };
          };
          llm = makeHome { cats-llm.enable = true; };
          metrics = makeHome { cats-metrics.enable = true; };
          neither = makeHome { };
          variants = makeHome {
            cats-llm = {
              enable = true;
              desktop = {
                medium.variants = [
                  "providers"
                  "agents"
                ];
                small.enable = true;
                small.variants = [
                  "spend"
                  "agents"
                  "burn-rate"
                  "spend"
                ];
                font.family = "Helvetica Neue";
                font.size = 16;
                font.package = pkgs.nerd-fonts.jetbrains-mono;
                opacity = 0.75;
              };
            };
          };
          menuOnly = makeHome {
            cats-metrics = {
              enable = true;
              desktop.overview.enable = false;
            };
          };
        in
        self.packages.${system}
        // {
          swift-style = pkgs.runCommand "cats-swift-style" { nativeBuildInputs = [ pkgs.swift-format ]; } ''
            bash ${self}/scripts/format-swift.sh check
            touch "$out"
          '';
          home-manager =
            assert !(llm.config.launchd.agents ? cats-metrics);
            assert !(metrics.config.launchd.agents ? cats-llm);
            assert !(neither.config.launchd.agents ? cats-llm);
            assert !(neither.config.launchd.agents ? cats-metrics);
            assert
              both.config.launchd.agents.cats-llm-app.config.EnvironmentVariables.CATS_LLM_WIDGETS
              == "large,medium";
            assert
              both.config.launchd.agents.cats-metrics-app.config.EnvironmentVariables.CATS_METRICS_POSITION
              == "bottom-left";
            assert
              menuOnly.config.launchd.agents.cats-metrics-app.config.EnvironmentVariables.CATS_METRICS_WIDGETS
              == "";
            assert
              variants.config.launchd.agents.cats-llm-app.config.EnvironmentVariables.CATS_LLM_WIDGETS
              == "large,medium,medium-agents,small,small-agents,small-burn-rate";
            assert
              variants.config.launchd.agents.cats-llm-app.config.EnvironmentVariables.CATS_LLM_FONT_SIZE == "16";
            assert
              variants.config.launchd.agents.cats-llm-app.config.EnvironmentVariables.CATS_LLM_FONT_FAMILY
              == "Helvetica Neue";
            assert
              variants.config.launchd.agents.cats-llm-app.config.EnvironmentVariables.CATS_LLM_OPACITY
              == "0.750000";
            assert builtins.elem pkgs.nerd-fonts.jetbrains-mono variants.config.home.packages;
            pkgs.runCommand "cats-home-manager-check" { } ''
              mkdir -p config/themes
              cp ${both.config.xdg.configFile."cats-metrics/config.toml".source} config/config.toml
              cp ${both.config.xdg.configFile."cats-metrics/themes/custom.toml".source} config/themes/custom.toml
              ${
                self.packages.${system}.cats-metrics
              }/bin/cats-metrics --config "$PWD/config/config.toml" config > "$out"
              test -f ${both.activationPackage}/LaunchAgents/org.nix-community.home.cats-llm.plist
              test -f ${both.activationPackage}/LaunchAgents/org.nix-community.home.cats-metrics.plist
            '';
        }
      );
    };
}
