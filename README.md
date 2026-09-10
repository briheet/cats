# Cats

Local AI usage, at a glance. Cats reads Claude Code, Codex, and local-agent logs
and displays token usage, estimated spend, and session activity on your desktop.

Choose a large overview, medium provider card, or small spend card. Use Nord,
Rosé Pine, or your own palette. Cards sit behind normal windows; the menu bar and
dashboard provide details and managed-agent controls.

## Install with Home Manager

Requires macOS 14 or later. The default Nix setup targets Apple Silicon.
No Apple Developer account or signing certificate is needed.

1. Add `github:briheet/cats` to your flake inputs.
2. Import `inputs.cats.homeManagerModules.default` in a Home Manager module.
3. Enable `programs.cats.enable = true;` and apply your configuration.

Follow the [complete Nix setup](docs/nix-setup.md) for copyable flake/module
examples, card switches, updates, and troubleshooting.

## What to expect

- Spend is an API-equivalent estimate, not a subscription bill or remaining quota.
- Activity comes from log events, not detecting open application windows.
- The UI refreshes every five seconds, without publishing unchanged readings.
- Data stays local. Cats stores usage metadata, not conversation text.
- Cards are desktop overlays, not Apple Widget Gallery widgets.

Read [settings and themes](docs/configuration.md),
[accounting](docs/pricing.md), or [architecture and limits](docs/desktop-architecture.md).
