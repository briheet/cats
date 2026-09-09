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
      description = "Collector package, or null to manage configuration only.";
    };
    appPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional package containing Applications/Cats.app, built and signed using Xcode.";
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
    service.enable = lib.mkEnableOption "the Cats launchd collector (independent of the app)";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Cats requires macOS.";
      }
      {
        assertion = !cfg.service.enable || cfg.package != null;
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
      lib.optional (cfg.package != null) cfg.package
      ++ lib.optional (cfg.appPackage != null) cfg.appPackage;
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
          "${cfg.package}/bin/cats"
          "--config"
          "${config.xdg.configHome}/cats/config.toml"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        EnvironmentVariables.HOME = config.home.homeDirectory;
      };
    };
  };
}
