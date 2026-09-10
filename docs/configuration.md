# Configuration and Nix

Cats follows the small-file approach used by [Helix](https://docs.helix-editor.com/themes.html): one TOML configuration and named, inheritable themes. The Home Manager interface follows its [Helix module](https://github.com/nix-community/home-manager/blob/master/modules/programs/helix.nix).

## Application settings

Create `~/.config/cats/config.toml` (or `$XDG_CONFIG_HOME/cats/config.toml`):

```toml
theme = "rose-pine-moon"
budget-usd = 20
# Optional absolute paths; ~/ is expanded.
# claude-dir = "~/.claude/projects"
# codex-dir = "~/.codex/sessions"
```

Run `cats config` to validate and print resolved settings without starting a collector or writing data. `cats --config /absolute/path/config.toml config` selects another file; `CATS_CONFIG` also works. CLI/environment budget and data-directory overrides take precedence over TOML. Explicit source-directory settings override the provider environment defaults. Unknown settings, invalid budgets, colors, theme names, and inheritance cycles are errors.

Budget and theme changes reload within 60 seconds. Invalid edits retain the last valid configuration and emit a warning. Storage/source changes require a collector restart. Desktop panels read the resulting snapshot every five seconds.

Storage defaults to `~/Library/Application Support/Cats`. Home Manager passes `settings.data-dir` to both processes; use an absolute path there. Direct desktop launches resolve the same TOML configuration through `cats config`; `CATS_DATA_DIR` overrides it for both processes.

## Themes

`cats themes` prints the built-in theme catalog as resolved JSON. `just preview` renders the production cards in each built-in theme into `build/previews/`; no preview code is shipped in the app.

Built-ins: `cats` (adaptive glass), `nord`, `rose-pine`, `rose-pine-moon`, and `rose-pine-dawn` (light). Colors come from the official [Nord palette](https://www.nordtheme.com/docs/colors-and-palettes/) and [Rosé Pine palette](https://github.com/rose-pine/palette/blob/main/palette.json).

Create `themes/my-nord.toml` beside the selected configuration:

```toml
inherits = "nord"
[colors]
accent = "#88c0d0"
```

Then set `theme = "my-nord"`. Built-in names are reserved. Inheritance merges semantic colors: `surface`, `text`, `muted`, `accent`, `secondary`, `claude`, `codex`, `warning`, and `error`. Values must be `#RRGGBB`. `appearance` accepts `system`, `dark`, or `light`; omitted values inherit. Glass geometry, blur, accessibility behavior, and layout stay consistent across themes. Rust resolves themes into the shared snapshot; SwiftUI only renders them, including the desktop panels. This is inspired by Helix, not a parser for Helix syntax-highlighting themes.

## Flake and Home Manager

```nix
# In your flake inputs:
inputs.cats.url = "github:briheet/cats";
inputs.cats.inputs.nixpkgs.follows = "nixpkgs";
inputs.cats.inputs.home-manager.follows = "home-manager";

# In a Home Manager module with inputs in scope:
imports = [ inputs.cats.homeManagerModules.default ];
programs.cats = {
  enable = true;
  desktop = {
    enable = true;
    position = "top-right";
    margin = 24;
    large.enable = true;
    medium.enable = false;
    small.enable = true;
  };
  settings = {
    budget-usd = 30;
    theme = "my-nord";
  };
  themes.my-nord = {
    inherits = "nord";
    colors.accent = "#88c0d0";
  };
};
```

`themes` also accepts TOML strings and Nix paths. Set `desktop.enable = false` for headless collection, or disable both `desktop.enable` and `service.enable` to install without starting anything.

Card switches are independent: large is the overview (340 × 340), medium shows providers
(340 × 170), and small shows spend and budget (170 × 170). Large and medium default to
enabled; small defaults to disabled. Enabled cards stack in large/medium/small order.
Setting all three to false leaves only the menu bar UI. Apply Home Manager to change
the selection. For direct launches, use `CATS_WIDGETS=large,small cats-desktop`; an empty
`CATS_WIDGETS` selects no cards, and an unset variable uses the defaults.

The module builds the Rust collector and Swift/AppKit UI directly from source. No Apple account, certificate, prebuilt bundle, App Group or widget registration is needed. Nix's compiler/linker tooling handles the minimal ARM64 ad-hoc signatures.

The default Nixpkgs input supports Apple Silicon. Intel users must supply Nixpkgs 26.05 Darwin (and a matching Home Manager version): Nixpkgs 26.11 removed `x86_64-darwin`. Cats exposes Intel package outputs only when the supplied Nixpkgs still supports them. Native Intel builds remain covered by the source-build CI; Intel Nix builds need separate verification.

Use `nix build`, `nix build .#cats-desktop`, `nix run . -- config`, `nix develop`, and `nix flake check`. The overlay exports `pkgs.cats` and `pkgs.cats-desktop`; the module does not need it.

Pass `inputs` through Home Manager's `extraSpecialArgs`, then import your common Cats module from your host's Home Manager modules. Both services run as your user; neither restarts on failure. They never request Accessibility, Screen Recording or Full Disk Access. Protected source paths may still be denied by macOS: change the configured source rather than granting broad access.

Migration: remove the old `appPackage`, `app.autostart`, `lib.mkApp` and local app flake input. No automatic migration reads the old Group Container. Re-importing the original telemetry logs reconstructs the cache. If you previously disabled Cats using `launchctl disable`, it remains disabled until explicitly re-enabled.

Configuration contains no API keys; Nix-generated files are public in the store. Checks never activate Home Manager.
