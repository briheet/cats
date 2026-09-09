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

Budget and theme changes reload within 60 seconds. Invalid edits retain the last valid configuration and emit a warning. Storage/source changes require a collector restart. Widgets update on their next system-controlled timeline refresh; the open app requests refreshes when snapshots change.

Do not change `data-dir` for ordinary desktop use: the sandboxed widget needs the shared App Group location. This advanced override is intended for isolated collector tests; a CLI override alone cannot relocate the widget's container.

## Themes

`cats themes` prints the built-in theme catalog as resolved JSON. Preview the production views with `just preview`: [Nord](preview-nord.png), [Rosé Pine](preview-rose-pine.png), [Moon](preview-rose-pine-moon.png), [Dawn](preview-rose-pine-dawn.png).

Built-ins: `cats` (adaptive glass), `nord`, `rose-pine`, `rose-pine-moon`, and `rose-pine-dawn` (light). Colors come from the official [Nord palette](https://www.nordtheme.com/docs/colors-and-palettes/) and [Rosé Pine palette](https://github.com/rose-pine/palette/blob/main/palette.json).

Create `themes/my-nord.toml` beside the selected configuration:

```toml
inherits = "nord"
[colors]
accent = "#88c0d0"
```

Then set `theme = "my-nord"`. Built-in names are reserved. Inheritance merges semantic colors: `surface`, `text`, `muted`, `accent`, `secondary`, `claude`, `codex`, `warning`, and `error`. Values must be `#RRGGBB`. `appearance` accepts `system`, `dark`, or `light`; omitted values inherit. Glass geometry, blur, accessibility behavior, and layout stay consistent across themes. Rust resolves themes into the shared snapshot; SwiftUI only renders them, including inside the sandboxed widget. This is inspired by Helix, not a parser for Helix syntax-highlighting themes.

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
  service.enable = true;
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

`themes` also accepts TOML strings and Nix paths. For files-only configuration, set `package = null`, `appPackage = null`, and `service.enable = false`. The module uses a pinned signed bundle when available, with its embedded collector. Until the first signed release is published and pinned, it warns and installs only the collector unless `appPackage` is supplied. See [widget distribution](releasing.md) for the complete setup and current limitations. Supported systems are Apple Silicon and Intel macOS.

Use `nix build`, `nix run . -- config`, `nix develop`, and `nix flake check`. The exported `overlays.default` adds `pkgs.cats`; using the Home Manager module does not require the overlay. `just build` remains the native Xcode build path. Signing and WidgetKit registration are separate from Nix packaging.

To include an existing Xcode-built bundle in Home Manager, use `programs.cats.appPackage = inputs.cats.lib.mkApp { inherit pkgs; src = /absolute/path/to/Cats.app; };`. This imports the bundle without binary fixups; it does not build or sign it. Use a signed release bundle for desktop widget registration. With a nonstandard `xdg.configHome`, enable the service (it passes the explicit config path); Finder-launched apps do not inherit your shell's XDG variables.

The launchd service is optional and does not require keeping Cats.app open. Both collectors use the same single-instance lock, so a service and an embedded helper cannot write concurrently. Quit the app before first enabling the service to avoid restart retries until its embedded collector exits. Configuration contains no API keys; Nix-generated files are public in the store. No Home Manager activation is performed by this repository's checks.
