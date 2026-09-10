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
    desktop.small.variants = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "spend"
          "agents"
          "burn-rate"
        ]
      );
      default = [ "spend" ];
      description = "Small cards to display; duplicates are ignored.";
    };
    desktop.medium.variants = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "providers"
          "agents"
        ]
      );
      default = [ "providers" ];
      description = "Medium cards to display; duplicates are ignored.";
    };
    desktop.font.family = lib.mkOption {
      type = lib.types.str;
      default = "system";
      description = "Installed font family or PostScript name; system uses the macOS default.";
    };
    desktop.font.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.nerd-fonts.jetbrains-mono";
      description = "Optional font package installed with the desktop UI.";
    };
    desktop.font.size = lib.mkOption {
      type = lib.types.ints.between 10 20;
      default = 12;
      description = "Base text size in points. Cards scale proportionally to preserve layout.";
    };
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
    home.packages = [
      cfg.package
    ]
    ++ lib.optionals cfg.desktop.enable (
      [ cfg.desktop.package ] ++ lib.optional (cfg.desktop.font.package != null) cfg.desktop.font.package
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
          CATS_FONT_FAMILY = cfg.desktop.font.family;
          CATS_FONT_SIZE = toString cfg.desktop.font.size;
          CATS_WIDGETS = lib.concatStringsSep "," (
            lib.optional cfg.desktop.large.enable "large"
            ++ lib.optionals cfg.desktop.medium.enable (
              map (variant: if variant == "providers" then "medium" else "medium-agents") (
                lib.unique cfg.desktop.medium.variants
              )
            )
            ++ lib.optionals cfg.desktop.small.enable (
              map (variant: if variant == "spend" then "small" else "small-${variant}") (
                lib.unique cfg.desktop.small.variants
              )
            )
          );
        };
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
  };
}
