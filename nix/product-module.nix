product:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "cats-${product}";
  metrics = product == "metrics";
  prefix = if metrics then "CATS_METRICS" else "CATS_LLM";
  cfg = config.programs.${name};
  toml = pkgs.formats.toml { };
  env = values: lib.mapAttrs' (key: value: lib.nameValuePair "${prefix}_${key}" value) values;
  environment = {
    HOME = config.home.homeDirectory;
  }
  // env {
    CONFIG = "${config.xdg.configHome}/${name}/config.toml";
    DATA_DIR = cfg.settings.data-dir;
    COLLECTOR = lib.getExe cfg.package;
  };
  widgets =
    if metrics then
      lib.optional cfg.desktop.overview.enable "overview"
    else
      lib.optional cfg.desktop.large.enable "large"
      ++ lib.optionals cfg.desktop.medium.enable (
        map (v: if v == "providers" then "medium" else "medium-agents") (
          lib.unique cfg.desktop.medium.variants
        )
      )
      ++ lib.optionals cfg.desktop.small.enable (
        map (v: if v == "spend" then "small" else "small-${v}") (lib.unique cfg.desktop.small.variants)
      );
in
{
  options.programs.${name} = {
    enable = lib.mkEnableOption "Cats ${product}";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { inherit product; };
    };
    service.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the independent collector at login.";
    };
    settings = lib.mkOption {
      type = toml.type;
      default = { };
      description = "Validated collector TOML settings. Changes require a restart for Metrics.";
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
      description = "Named custom themes; shared built-ins need no definition.";
    };
    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ./desktop.nix {
          inherit product;
          collector = cfg.package;
        };
      };
      position = lib.mkOption {
        type = lib.types.enum (
          if metrics then
            [
              "top-left"
              "top-right"
              "bottom-left"
              "bottom-right"
            ]
          else
            [
              "top-left"
              "top-right"
            ]
        );
        default = if metrics then "bottom-left" else "top-right";
      };
      margin = lib.mkOption {
        type = lib.types.ints.between 0 200;
        default = 24;
      };
      opacity = lib.mkOption {
        type = lib.types.addCheck (lib.types.either lib.types.int lib.types.float) (v: v >= 0 && v <= 1);
        default = 1.0;
      };
      font = {
        family = lib.mkOption {
          type = lib.types.str;
          default = "system";
        };
        size = lib.mkOption {
          type = lib.types.ints.between 10 20;
          default = 12;
        };
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
        };
      };
    }
    // (
      if metrics then
        {
          overview.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Show the 340 × 170 metrics overview.";
          };
        }
      else
        {
          large.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          medium.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          medium.variants = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "providers"
                "agents"
              ]
            );
            default = [ "providers" ];
          };
          small.enable = lib.mkEnableOption "small LLM cards";
          small.variants = lib.mkOption {
            type = lib.types.listOf (
              lib.types.enum [
                "spend"
                "agents"
                "burn-rate"
              ]
            );
            default = [ "spend" ];
          };
        }
    );
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "${name} requires macOS.";
      }
      {
        assertion = builtins.isString cfg.settings.data-dir && lib.hasPrefix "/" cfg.settings.data-dir;
        message = "${name} data-dir must be absolute.";
      }
      {
        assertion = lib.all (
          n:
          builtins.match "[a-zA-Z0-9_-]+" n != null
          && !(builtins.elem n [
            "cats"
            "nord"
            "gruvbox"
            "catppuccin-mocha"
            "rose-pine"
            "rose-pine-moon"
            "rose-pine-dawn"
          ])
        ) (builtins.attrNames cfg.themes);
        message = "${name} custom theme names must be safe and cannot shadow built-ins.";
      }
    ];
    programs.${name}.settings.data-dir =
      lib.mkDefault "${config.home.homeDirectory}/Library/Application Support/${
        if metrics then "CatsMetrics" else "CatsLLM"
      }";
    home.packages = [
      cfg.package
    ]
    ++ lib.optionals cfg.desktop.enable (
      [ cfg.desktop.package ] ++ lib.optional (cfg.desktop.font.package != null) cfg.desktop.font.package
    );
    xdg.configFile = {
      "${name}/config.toml".source = toml.generate "${name}-config.toml" cfg.settings;
    }
    // lib.mapAttrs' (
      themeName: value:
      lib.nameValuePair "${name}/themes/${themeName}.toml" {
        source =
          if builtins.isPath value then
            value
          else if builtins.isString value then
            pkgs.writeText "${name}-${themeName}.toml" value
          else
            toml.generate "${name}-${themeName}.toml" value;
      }
    ) cfg.themes;
    launchd.agents.${name} = lib.mkIf cfg.service.enable {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe cfg.package) ];
        EnvironmentVariables = environment;
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
    launchd.agents."${name}-app" = lib.mkIf cfg.desktop.enable {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe cfg.desktop.package) ];
        EnvironmentVariables =
          environment
          // env {
            EXTERNAL_COLLECTOR = "1";
            POSITION = cfg.desktop.position;
            MARGIN = toString cfg.desktop.margin;
            FONT_FAMILY = cfg.desktop.font.family;
            FONT_SIZE = toString cfg.desktop.font.size;
            OPACITY = toString cfg.desktop.opacity;
            WIDGETS = lib.concatStringsSep "," widgets;
          };
        RunAtLoad = true;
        KeepAlive = false;
      };
    };
  };
}
