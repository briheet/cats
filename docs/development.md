# Development

## Build and test

Use `nix develop` for pinned Rust and formatting tools. Native Swift commands
require Apple's developer tools; Nix package builds supply their own Swift compiler
and SDK. For an ad-hoc missing tool, use `nix-shell -p TOOL`.

```sh
just fmt                     # Rust and Swift formatting
just check                   # Formatting and Clippy
just test                    # Rust integration and Swift model/storage tests
just build                   # Local bundle; does not launch it
just smoke                   # Isolated ingestion, process control, single-writer lock
just desktop-selection-smoke # Briefly opens each of eight card combinations
just preview                 # Synthetic previews and corner checks across six themes
just profile-ui              # Synthetic 20k-record import and 70-second UI CPU/RSS sample
just refresh-smoke           # Actual five-second AppState refresh and deduplication
nix flake check              # Packages, Swift style, Home Manager configuration
```

`just open` builds and launches the app using your real configuration. Tests must
use temporary storage and synthetic logs. Never activate Home Manager or change
macOS privacy settings as part of a test.

## Source boundaries

| Location | Responsibility |
| --- | --- |
| `rust/src/collectors/` | `Parser` trait and provider implementations; bounded JSONL reading |
| `rust/src/domain.rs` | Provider/status/budget enums and status aging |
| `rust/src/{storage,aggregation,telemetry}.rs` | Persistence, queries, pricing |
| `rust/src/{service,managed,shutdown}.rs` | Collection and owned process groups |
| `macos/CatsApp/` | AppKit lifecycle, observable state, collector process |
| `macos/Shared/` | Codable snapshots, storage reader, formatting; Swift test target |
| `macos/Views/` | Production UI |
| `macos/Preview/` | Preview compositions, excluded from application builds |
| `nix/` | Packages and Home Manager options |

Keep pricing/configuration in Rust and rendering in Swift. Use typed messages,
explicit resource ownership, main-actor UI state, and weak recurring callbacks.
Propagate recoverable errors; document unsafe invariants. Do not panic on log
input, guess unknown prices, store conversations, or retry denied access.

Preserve JSON/TOML compatibility. Add a regression test when changing parsing,
accounting, status rules, or configuration behavior. Preview production cards,
not a separate mock implementation.

## Measure, then claim

`just smoke` writes `build/smoke-report.json`. `CATS_SMOKE_PROFILE=1 just smoke`
collects additional samples. `just profile` runs the optimized collector against
configured sources until interrupted; use temporary sources for benchmarks.

Report workload size, duration, build mode, and platform with results. Collector
measurements combine ingestion with SQLite writes and aggregation with queries;
they do not measure UI rendering. A short smoke test is not sustained CPU, battery,
or large-history profiling.

See [UI workload measurements](performance.md) for the latest bounded run and its limits.

## Style references

Follow the [Rust API guidelines](https://rust-lang.github.io/api-guidelines/checklist.html),
[Rust style guide](https://doc.rust-lang.org/style-guide/), and
[Swift API guidelines](https://www.swift.org/documentation/api-design-guidelines/).
Use rustfmt and swift-format. Prefer short, explicit code over compressed expressions.

[Local-agent integrations](local-agents.md) use the same collector without adding a provider parser.
