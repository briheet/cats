# Code guidelines

Use the [Rust API guidelines](https://rust-lang.github.io/api-guidelines/checklist.html),
[Rust style guide](https://doc.rust-lang.org/style-guide/),
[Swift API guidelines](https://www.swift.org/documentation/api-design-guidelines/), and
[Swift concurrency model](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/).
Prefer clarity over compressed one-liners. Use rustfmt and
[swift-format](https://github.com/swiftlang/swift-format), not hand-maintained formatting.

## Boundaries

```text
rust/src/
  main.rs             CLI dispatch and startup
  service.rs          bounded ingestion and snapshot publication
  managed.rs          control of explicitly launched child process groups
  shutdown.rs         signal handling
  collectors/         file cursors and provider parsers
  aggregation.rs      accounting queries and snapshot assembly
  storage.rs          SQLite persistence
macos/
  CatsApp/            AppKit lifecycle, window ownership and collector process
  Shared/             Codable models, explicit snapshot storage and formatting
  Views/              reusable production SwiftUI components
  Preview/            development-only render compositions
```

- Keep Rust responsible for configuration, pricing and aggregation. Swift renders
  snapshots; do not duplicate business rules or TOML parsing there.
- Own resources explicitly. App state must not own views that retain that state.
  Snapshot stores take a directory instead of consulting mutable global state.
- Keep UI state on the main actor and capture owners weakly in recurring callbacks.
- Use named types for control messages and state with multiple fields. Keep the
  JSON/TOML wire formats backward-compatible; don't rename protocol keys for style.
- Propagate recoverable errors, document unsafe invariants, and don't panic on
  external data. Unknown model prices stay unknown, never guessed.
- Bound memory and processing per log batch. Commit cursors atomically with usage.
- Never persist conversation text, grant broad access or retry permission denials.
- Remove unused features instead of retaining speculative variants. Keep preview
  code out of application builds, and preview the actual production components.

## Verification

Use `nix develop` for the pinned tool versions, then:

```sh
just fmt             # Rust + Swift formatting
just check           # formatting, Swift lint and Clippy
just test            # Rust integration and Swift model/storage tests
just build
just smoke           # isolated telemetry and process-control test
just desktop-smoke   # briefly opens isolated cards, then stops them
just preview         # actual card previews in build/previews/
nix flake check      # packages, Home Manager generation and Swift formatting
```

Tests must use their own temporary storage and must not activate Home Manager,
start real-user collection, or alter macOS privacy settings.
