# Cats

**Desktop overlays:** Cats uses its own native glass panels, not WidgetKit. Install through a Home Manager flake without an Apple Developer account, certificates, App Groups, or widget registration. See [configuration](docs/configuration.md).

A small, local-first macOS companion for Claude, Codex, and local agents. Rust collects usage and produces one snapshot; SwiftUI presents two glass desktop cards, a menu-bar panel and an optional dashboard.


## Develop

Requires macOS 14+. The Nix package supplies build dependencies; the local build uses Apple's Swift tools and Rust. Optional tools come from Nix:

```sh
nix-shell -p just rustfmt clippy
just test
just check
just build
just open
```

The local build produces `build/Build/Products/Release/Cats.app`, including desktop panels and the Rust collector. `just install` preserves a previously managed bundle and refuses unmanaged installations. `just preview` renders the actual desktop cards into `build/previews/` using synthetic fixtures. Preview-only code is not compiled into the app. See [CONTRIBUTING.md](CONTRIBUTING.md) for the source layout and coding guidelines.

Desktop cards appear at the top-right of the primary display, below ordinary windows, and can be dragged. The menu has **Show widgets** to reset placement. Home Manager supports `desktop.position` and `desktop.margin`. These cards do not appear in Apple's Widget Gallery. See [distribution](docs/releasing.md).

## Collect

```sh
just run --once
just run --profile
cargo run -- --data-dir /tmp/cats-dev --budget 30 --once
```

Cats reads Claude Code's `~/.claude/projects/**/*.jsonl` and Codex's `~/.codex/sessions/**/*.jsonl`. Override their base directories with `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. `CATS_DATA_DIR` changes shared storage and `CATS_BUDGET_USD` changes the default $20 budget. The app starts its embedded collector; use the standalone command for headless operation. Only one collector may write to a data directory at a time.

The first run imports available history. Subsequent runs resume persisted byte offsets. Watchers process changed files, with a once-per-minute reconciliation for missed notifications and newly created source directories. Oversized lines are skipped at a 1 MiB limit; transactions process at most about 4 MiB at a time. Missing providers are normal. Malformed JSON records are skipped with warnings; transient file failures back off up to 256 seconds. Permission denial stops collection.

SQLite stores token metadata, session/agent identities, file cursors, and estimated costs. No prompts, messages, code, credentials, or raw log records are persisted. Cats makes no network requests. SQLite lives in `~/Library/Application Support/Cats` alongside an atomically replaced `cats-state.json`. A separate heartbeat distinguishes an idle collector from a stopped collector without rewriting unchanged snapshots.

## Accounting

Spend is an **API-equivalent estimate**, not a subscription invoice or remaining provider quota. Current supported rates and limitations are in [docs/pricing.md](docs/pricing.md). Unknown models retain token usage and are flagged as unpriced. Cache reads, short cache writes, long cache writes, uncached input, and output are disjoint. Codex reasoning output is already included in output tokens.

Daily totals use local calendar boundaries. Burn rate uses the trailing 30 minutes, including across midnight. Projections need at least two priced events spanning five minutes and are suppressed when today's pricing is incomplete. Provider totals and token counts are for today; agent spend is for the agent's session. The large widget shows four agents, ordered running, waiting, failed, completed. Silence beyond five minutes is shown as waiting, because log silence does not establish completion. Claude/Codex formats are not stable public telemetry contracts; fixtures and conservative fallbacks make changes explicit.

## Managed agents

```sh
cargo run -- run tests -- cargo test
cargo run -- run backend -- codex exec 'Run the backend checks'
```

Pause/resume controls apply to subprocess groups launched through `cats run`. Each wrapper owns its group and never signals processes discovered by name. These wrappers are intended for noninteractive commands. Existing Claude/Codex sessions are observed only. Pausing is a process suspension; it does not cancel already submitted remote API work or guarantee that billing stops.

The wrapper publishes lifecycle metadata in `agents/*.jsonl`. A local agent can also submit per-request usage using the protocol in [docs/local-agents.md](docs/local-agents.md). The menu and optional dashboard expose managed-agent controls.

## Verify and profile

```sh
just test       # Rust integration tests and Swift snapshot tests
just check      # rustfmt, Clippy and swift-format lint
just smoke     # isolated live ingestion, process controls, single-writer lock
just profile   # optimized collector, Ctrl-C to stop
CATS_SMOKE_PROFILE=1 just smoke
```

The smoke test uses temporary provider logs and child processes, and saves measurements in `build/smoke-report.json`. Profiling samples its own process with `sysinfo` and records bounded latency samples only in profiling mode. Ingestion and SQLite transaction timing are measured together; aggregation includes query time. These combined metrics are conservative end-to-end measurements, not isolated SQLite benchmarks. The background collector wakes once per second to check shutdown and performs reconciliation/aggregation every minute when idle. The Swift companion reads the compact snapshot every five seconds. Permission denial stops polling and collection rather than triggering a restart loop.

See [desktop architecture](docs/desktop-architecture.md) for current decisions and limitations.

## Declarative configuration

Cats supports TOML settings, Nord and Rosé Pine themes, custom theme inheritance, and a Home Manager module. See [configuration and Nix](docs/configuration.md). `nix build` packages both collector and desktop UI; `nix build .#cats` builds only the collector; `just build` builds the local desktop bundle.
