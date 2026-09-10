# Desktop architecture

Cats is a native desktop overlay, not a WidgetKit extension. The original
WidgetKit sections of `plan.md` are superseded by this document.

## Components

See [the code guidelines](../CONTRIBUTING.md) for the source layout and upstream
Rust/Swift conventions. Observable state owns no windows; snapshot stores use
explicit directories, and preview code is separate from production views.

1. Rust owns collection, accounting, SQLite metadata/cursors, TOML configuration,
   theme resolution and atomic JSON snapshots. No UI business logic is duplicated.
2. AppKit owns the application lifecycle, a menu-bar item, two borderless desktop
   panels and an optional dashboard. SwiftUI renders the existing glass components.
3. Home Manager writes TOML and starts independent collector/UI LaunchAgents.
   The UI never starts another collector when Home Manager owns collection.

Panels sit above desktop icons and below normal windows, join Spaces without
activation, and reposition when display geometry changes. They can be dragged;
the menu's Show widgets action restores the configured top-left/top-right anchor.
Dragging is session-local; Home Manager owns initial placement and margin.

## Packaging and security

Nix builds Rust and Swift directly from pinned sources, using its Swift compiler
and Apple SDK. The package contains normal executables, not extensions. The
compiler/linker and Darwin fixups handle ARM64 ad-hoc signatures; no Apple
account, certificate, signing secret or notarization service is involved.

Storage is under `~/Library/Application Support/Cats` unless explicitly changed.
The obsolete `CATS_APP_GROUP` environment variable is ignored. Cats never probes
or migrates the old Group Container. It reads only configured telemetry sources;
permission denial stops the collector or UI polling. LaunchAgents do not restart
failed processes, avoiding repeated permission prompts.

## Verification

- Rust integration tests cover accounting, configuration, legacy-group isolation
  and permission denial.
- Swift tests cover snapshot decoding, stale/corrupt data and denied access.
- `just desktop-smoke` starts an isolated UI with collection disabled, checks its
  two window sizes/levels through metadata (no screen capture), and stops it.
- `just smoke` tests live collection, single-instance locking and managed agents.
- `nix flake check` builds the UI/collector and a Home Manager test generation;
  it never activates that generation or touches real launch agents.

## Limits

These cards do not appear in Apple's Widget Gallery. Native glass-button APIs
use a fallback when building with Nix's older Swift compiler/SDK. Layout currently
supports two cards on the primary display; per-card and per-monitor layouts can
be added without changing collection or packaging.
