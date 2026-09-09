# Cats

**Widget release status:** no signed public widget release is available yet. The collector works; installing it alone does not install the widget. See [widget installation and releases](docs/releasing.md) for the Home Manager bundle setup and signing requirements.

A small, local-first macOS companion for Claude, Codex, and local agents. Rust collects usage and produces one snapshot; SwiftUI presents it in a glass menu-bar panel, a native window, and small through extra-large widgets. Spend, agent, and burn-rate variants follow the supplied visual reference.

![Cats widgets in dark mode](docs/preview-dark.png)

## Develop

Requires macOS 14+, full Xcode, and Rust. Optional tools come from Nix:

```sh
nix-shell -p just xcodegen rustfmt clippy
just test
just check
just build
just open
```

The build uses Xcode's SDK and compiler tools even inside a Nix shell. It produces `build/Build/Products/Release/Cats.app`, including the Rust collector and widget extension. `just install` copies it to `~/Applications` without overwriting an existing app. `just preview` renders the actual widget views into `docs/preview-{dark,light}.png` and a native-size validation sheet in `build/native-sizes.png`, using synthetic fixtures. The component breakdown and Apple design references are in [docs/design-plan.md](docs/design-plan.md).

`just build` uses ad-hoc development signing for the current Mac's architecture, retaining the widget sandbox entitlement. This is not a distributable widget release. See [the release guide](docs/releasing.md) for Developer ID signing, team-prefixed App Groups, notarization, and the Home Manager installation path. Widget gallery visibility on a signed installation has not yet been verified.

## Collect

```sh
just run --once
just run --profile
cargo run -- --data-dir /tmp/cats-dev --budget 30 --once
```

Cats reads Claude Code's `~/.claude/projects/**/*.jsonl` and Codex's `~/.codex/sessions/**/*.jsonl`. Override their base directories with `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. `CATS_DATA_DIR` changes shared storage and `CATS_BUDGET_USD` changes the default $20 budget. The app starts its embedded collector; use the standalone command for headless operation. Only one collector may write to a data directory at a time.

The first run imports available history. Subsequent runs resume persisted byte offsets. Watchers process changed files, with a once-per-minute reconciliation for missed notifications and newly created source directories. Oversized lines are skipped at a 1 MiB limit; transactions process at most about 4 MiB at a time. Missing providers are normal. Malformed JSON records are skipped with warnings; file failures back off up to 256 seconds.

SQLite stores token metadata, session/agent identities, file cursors, and estimated costs. No prompts, messages, code, credentials, or raw log records are persisted. Cats makes no network requests. SQLite lives in the private shared container alongside an atomically replaced `cats-state.json`. A separate heartbeat distinguishes an idle collector from a stopped collector without rewriting unchanged snapshots.

## Accounting

Spend is an **API-equivalent estimate**, not a subscription invoice or remaining provider quota. Current supported rates and limitations are in [docs/pricing.md](docs/pricing.md). Unknown models retain token usage and are flagged as unpriced. Cache reads, short cache writes, long cache writes, uncached input, and output are disjoint. Codex reasoning output is already included in output tokens.

Daily totals use local calendar boundaries. Burn rate uses the trailing 30 minutes, including across midnight. Projections need at least two priced events spanning five minutes and are suppressed when today's pricing is incomplete. Provider totals and token counts are for today; agent spend is for the agent's session. The large widget shows four agents, ordered running, waiting, failed, completed. Silence beyond five minutes is shown as waiting, because log silence does not establish completion. Claude/Codex formats are not stable public telemetry contracts; fixtures and conservative fallbacks make changes explicit.

## Managed agents

```sh
cargo run -- run tests -- cargo test
cargo run -- run backend -- codex exec 'Run the backend checks'
```

Pause/resume controls apply to subprocess groups launched through `cats run`. Each wrapper owns its group and never signals processes discovered by name. These wrappers are intended for noninteractive commands. Existing Claude/Codex sessions are observed only. Pausing is a process suspension; it does not cancel already submitted remote API work or guarantee that billing stops.

The wrapper publishes lifecycle metadata in `agents/*.jsonl`. A local agent can also submit per-request usage using the protocol in [docs/local-agents.md](docs/local-agents.md). App Intents expose pause, resume, and open actions; the main window exposes managed-agent controls.

## Verify and profile

```sh
just test       # Rust integration tests and Swift snapshot tests
just check      # rustfmt and Clippy with warnings denied
just smoke     # isolated live ingestion, process controls, single-writer lock
just profile   # optimized collector, Ctrl-C to stop
CATS_SMOKE_PROFILE=1 just smoke
```

The smoke test uses temporary provider logs and child processes, and saves measurements in `build/smoke-report.json`. Profiling samples its own process with `sysinfo` and records bounded latency samples only in profiling mode. Ingestion and SQLite transaction timing are measured together; aggregation includes query time. These combined metrics are conservative end-to-end measurements, not isolated SQLite benchmarks. The background collector wakes once per second to check shutdown and performs reconciliation/aggregation every minute when idle. The Swift companion reads the compact snapshot every five seconds and coalesces WidgetKit refresh requests to at most once a minute; WidgetKit decides actual delivery.

See [docs/plan.md](docs/plan.md) for the original design brief and [docs/implementation.md](docs/implementation.md) for implementation decisions and remaining limitations.

## Declarative configuration

Cats supports TOML settings, Nord and Rosé Pine themes, custom theme inheritance, and a Home Manager module. See [configuration and Nix](docs/configuration.md). `nix build` packages the collector; `just build` builds the native app and widgets with Xcode.
