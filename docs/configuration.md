# Settings and themes

For installation, imports, and service troubleshooting, see [Nix setup](nix-setup.md).

## Settings and paths

Home Manager writes `~/.config/cats/config.toml` (respecting `xdg.configHome`).
Without Home Manager, create this file yourself:

```toml
theme = "nord"
budget-usd = 20
# data-dir = "~/Library/Application Support/Cats"
# claude-dir = "~/.claude/projects"
# codex-dir = "~/.codex/sessions"
```

| Setting | Default / rule |
| --- | --- |
| `theme` | `cats`; a built-in or custom theme name |
| `budget-usd` | `20`; positive, finite USD amount |
| `data-dir` | `~/Library/Application Support/Cats` |
| `claude-dir` | `$CLAUDE_CONFIG_DIR/projects`, otherwise `~/.claude/projects` |
| `codex-dir` | `$CODEX_HOME/sessions`, otherwise `~/.codex/sessions` |

TOML paths accept absolute paths or `~/`. Home Manager's `settings.data-dir` must
be absolute. For a portable override, add `config` to the module arguments and use
`"${config.home.homeDirectory}/Library/Application Support/Cats"`.

`--config` / `CATS_CONFIG` selects a config file. For budget and storage, precedence
is CLI flag → environment (`CATS_BUDGET_USD`, `CATS_DATA_DIR`) → TOML → default.
Explicit TOML source directories override provider environment defaults.

Run `cats config` to validate and print resolved settings without starting collection.
Unknown keys and invalid values are rejected. Never put secrets in Nix settings:
generated files are readable in the Nix store.

Theme and budget reload within a minute; UI refresh can add five seconds.
Storage/source changes require a collector restart. Card selection requires a UI
restart; applying Home Manager handles the service configuration change.

For direct launches, `CATS_WIDGETS=large,small cats-desktop` selects cards.
An empty value selects none; an unset variable defaults to large and medium.

Additional IDs: `medium-agents`, `small-agents`, `small-burn-rate`. For typography,
use `CATS_FONT_FAMILY` and `CATS_FONT_SIZE` (10–20, default 12). Home Manager exposes
these as [variant lists and font options](nix-setup.md).

`CATS_OPACITY` controls glass-background opacity from 0 to 1 (default 1).
Text and charts stay opaque; 1 retains the standard translucent glass. macOS
Reduce Transparency takes precedence. Restart the UI after changing this value.

## Themes

Built-ins: `cats`, `nord`, `rose-pine`, `rose-pine-moon`, `rose-pine-dawn`,
`gruvbox` (dark), and `catppuccin-mocha`.
New palettes follow [Gruvbox](https://github.com/morhetz/gruvbox) and
[Catppuccin](https://github.com/catppuccin/palette).
List resolved palettes with `cats themes`.

```nix
programs.cats.settings.theme = "my-nord";
programs.cats.themes.my-nord = {
  inherits = "nord";
  colors.accent = "#88c0d0";
};
```

Without Home Manager, put equivalent TOML in `themes/my-nord.toml` beside your
config. Custom themes inherit missing values and cannot replace built-ins.
`themes` also accepts TOML text or a Nix path.

Color keys: `surface`, `text`, `muted`, `accent`, `secondary`, `claude`, `codex`,
`warning`, `error`. Values are `#RRGGBB`. `appearance` is `system`, `dark`, or `light`.
Themes change colors and appearance, not card geometry.
