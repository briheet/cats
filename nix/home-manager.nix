{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cats;
  toml = pkgs.formats.toml { };
  themeType = lib.types.oneOf [
    toml.type
    lib.types.path
    lib.types.lines
  ];
in
{
  options.programs.cats = {
    enable = lib.mkEnableOption "Cats telemetry and glass widgets";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "Collector-only package. When an app bundle is configured, Cats uses its embedded signed collector instead.";
    };
    appPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = import ./release.nix { inherit pkgs; };
      description = "Widget-containing bundle. Defaults to the pinned signed release when available; null is collector-only.";
    };
    settings = lib.mkOption {
      type = toml.type;
      default = { };
      example = {
        theme = "rose-pine-moon";
        budget-usd = 20;
      };
      description = "Settings written to the Cats TOML configuration.";
    };
    themes = lib.mkOption {
      type = lib.types.attrsOf themeType;
      default = { };
      description = "Custom themes as TOML attribute sets, TOML text, or paths. Built-in names are reserved.";
    };
    service.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the Cats collector through launchd.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.sessionVariables.CATS_APP_GROUP =
      if cfg.appPackage == null then
        "group.dev.cats.shared"
      else
        cfg.appPackage.appGroup or "group.dev.cats.shared";
    warnings =
      lib.optional (cfg.appPackage == null)
        "Cats: no signed widget release is pinned yet. Only the collector will be installed. Set programs.cats.appPackage to an Xcode-built bundle for development; see the Cats release guide.";
    home.activation.installCatsBundle = lib.mkIf (cfg.appPackage != null) (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
        run ${pkgs.bash}/bin/bash ${../scripts/install-bundle.sh} ${cfg.appPackage}/Applications/Cats.app ${lib.escapeShellArg "${config.home.homeDirectory}/Applications/Cats.app"}
      ''
    );
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Cats requires macOS.";
      }
      {
        assertion = !cfg.service.enable || cfg.package != null || cfg.appPackage != null;
        message = "Cats service requires a collector package.";
      }
      {
        assertion = lib.all (
          name:
          builtins.match "[a-zA-Z0-9_-]+" name != null
          && !(builtins.elem name [
            "cats"
            "nord"
            "rose-pine"
            "rose-pine-moon"
            "rose-pine-dawn"
          ])
        ) (builtins.attrNames cfg.themes);
        message = "Cats custom theme names must be safe file names and cannot shadow built-ins.";
      }
    ];
    home.packages =
      lib.optional (cfg.package != null && cfg.appPackage == null) cfg.package
      ++ lib.optional (cfg.appPackage != null) (
        pkgs.runCommand "cats-cli" { } ''
          mkdir -p "$out/bin"
          ln -s ${cfg.appPackage}/Applications/Cats.app/Contents/Helpers/cats "$out/bin/cats"
        ''
      );
    xdg.configFile = {
      "cats/config.toml".source = toml.generate "cats-config.toml" cfg.settings;
    }
    // lib.mapAttrs' (
      name: value:
      lib.nameValuePair "cats/themes/${name}.toml" {
        source =
          if builtins.isPath value then
            value
          else if builtins.isString value then
            pkgs.writeText "cats-theme-${name}.toml" value
          else
            toml.generate "cats-theme-${name}.toml" value;
      }
    ) cfg.themes;
    launchd.agents.cats = lib.mkIf cfg.service.enable {
      enable = true;
      config = {
        ProgramArguments = [
          (
            if cfg.appPackage != null then
              "${config.home.homeDirectory}/Applications/Cats.app/Contents/Helpers/cats"
            else
              "${cfg.package}/bin/cats"
          )
          "--config"
          "${config.xdg.configHome}/cats/config.toml"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        EnvironmentVariables.HOME = config.home.homeDirectory;
        EnvironmentVariables.CATS_APP_GROUP =
          if cfg.appPackage == null then
            "group.dev.cats.shared"
          else
            cfg.appPackage.appGroup or "group.dev.cats.shared";
      };
    };
    launchd.agents.cats-app = lib.mkIf (cfg.appPackage != null) {
      enable = true;
      config = {
        ProgramArguments = [ "${config.home.homeDirectory}/Applications/Cats.app/Contents/MacOS/Cats" ];
        RunAtLoad = true;
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          CATS_CONFIG = "${config.xdg.configHome}/cats/config.toml";
        };
      };
    };
  };
}
