{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.cats;
  toml = pkgs.formats.toml { };
  environment = {
    HOME = config.home.homeDirectory;
    CATS_CONFIG = "${config.xdg.configHome}/cats/config.toml";
    CATS_DATA_DIR = cfg.settings.data-dir;
    CATS_COLLECTOR = lib.getExe cfg.package;
  };
in
{
  options.programs.cats = {
    enable = lib.mkEnableOption "Cats local telemetry and desktop glass widgets";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "Rust telemetry collector.";
    };
    desktop.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./desktop.nix { cats = cfg.package; };
      description = "Native desktop panels, built without an Apple account.";
    };
    desktop.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start glass desktop panels at login.";
    };
    desktop.position = lib.mkOption {
      type = lib.types.enum [
        "top-right"
        "top-left"
      ];
      default = "top-right";
      description = "Initial widget position on the primary display.";
    };
    desktop.large.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show the large overview card (760 × 250 points, up to five agents).";
    };
    desktop.medium.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show the medium provider card (340 × 170 points).";
    };
    desktop.small.enable = lib.mkEnableOption "the small spend card (170 × 170 points)";
    desktop.margin = lib.mkOption {
      type = lib.types.ints.between 0 200;
      default = 24;
      description = "Distance from the display edge in points.";
    };
    service.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start collection at login. Permission failures do not restart.";
    };
    settings = lib.mkOption {
      type = toml.type;
      default = { };
      description = "Cats TOML settings, including theme, budget-usd and source directories.";
    };
    themes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          toml.type
          lib.types.path
          lib.types.lines
        ]
      );
      default = { };
      description = "Custom themes as TOML attributes, text, or files.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.isString cfg.settings.data-dir && lib.hasPrefix "/" cfg.settings.data-dir;
        message = "Cats Home Manager settings.data-dir must be an absolute path.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Cats requires macOS.";
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
        message = "Cats custom themes must have safe names and cannot shadow built-ins.";
      }
    ];
    programs.cats.settings.data-dir = lib.mkDefault "${config.home.homeDirectory}/Library/Application Support/Cats";
    home.packages = [ cfg.package ] ++ lib.optional cfg.desktop.enable cfg.desktop.package;
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
          (lib.getExe cfg.package)
          "--config"
          environment.CATS_CONFIG
        ];
        EnvironmentVariables = environment;
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
    launchd.agents.cats-app = lib.mkIf cfg.desktop.enable {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe cfg.desktop.package) ];
        EnvironmentVariables = environment // {
          CATS_EXTERNAL_COLLECTOR = "1";
          CATS_POSITION = cfg.desktop.position;
          CATS_MARGIN = toString cfg.desktop.margin;
          CATS_WIDGETS = lib.concatStringsSep "," (
            lib.filter (size: cfg.desktop.${size}.enable) [
              "large"
              "medium"
              "small"
            ]
          );
        };
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
  };
}
