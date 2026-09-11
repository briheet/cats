# Architecture

This page describes **Cats LLM**. See [ecosystem architecture](ecosystem.md) for
Cats Metrics, the split, and current installation names.

Cats separates collecting data from displaying it. The collector can run without
the UI; the UI can display its last snapshot without a live collector.

```text
JSONL logs → Rust collector → SQLite → JSON snapshot → SwiftUI
                   └──────── heartbeat ────────────────┘
```

## Ownership

| Component | Owns |
| --- | --- |
| Rust | Parsing, cursors, costs, aggregation, TOML, themes, snapshots |
| SwiftUI | Rendering and user actions; no pricing or database queries |
| AppKit | Panels, menu bar, dashboard, application lifecycle |
| Home Manager | Packages, generated configuration, two user LaunchAgents |

Home Manager starts the collector and UI separately. A directly launched UI may
start its collector; it stops only the child it owns. A file lock prevents two
collectors from writing to the same storage directory.

## Why SQLite?

Logs are inputs, not a ready-made dashboard. Cats needs durable file offsets,
deduplicated usage, and queries across sessions and time windows. SQLite provides
these in one local file, without a server. Usage and cursor updates commit in the
same transaction so restarting does not lose the ingestion position.

Storage defaults to `~/Library/Application Support/CatsLLM`:

| File | Purpose |
| --- | --- |
| `usage.sqlite` | Usage metadata, agent state, costs, file cursors |
| `state.json` | Atomically replaced UI snapshot |
| `heartbeat` | Collector health, independent of snapshot age |
| `control.json` | Desired pause/resume state for managed commands |
| `agents/*.jsonl` | Local-agent lifecycle and usage inputs |

Names and session identifiers persist. Prompts, messages, credentials, source
code, and raw provider records do not.

## Updates and failures

- File notifications trigger ingestion; a scan every minute catches missed changes.
- Lines over 1 MiB are skipped; batches read at most about 4 MiB.
- Malformed JSON is skipped. Transient file errors back off; denied access stops collection.
- Unchanged snapshots are not rewritten.
- The UI reads at startup and every five seconds, publishing only changed readings.
- Agent rows show time since last logged activity (`9h ago`), not turn duration.
  Missing timestamps display a dash. The obsolete elapsed-duration field is removed.
- Provider running/waiting records older than 30 minutes become idle in snapshots.
  Codex turn completion becomes idle after five minutes. Historical database rows
  are retained as source observations, not rewritten to claim current activity.
- A heartbeat older than 180 seconds marks collection unavailable at the next UI refresh.
- Invalid snapshots retain the last good data and show a warning.
- LaunchAgents do not automatically restart on failure.

## Code structure

Provider-specific structs implement the `Parser` trait. `ProviderKind`, `AgentStatus`,
and `BudgetState` represent internal domain values; strings exist at the JSON/SQLite
boundaries. Serde and SQL conversions retain existing persisted names. Status aging
belongs to the domain model, not SQL row assembly. See [development](development.md).

## Current limits

Cards use the primary display and wrap into rows. Six variants are available;
font size scales their geometry. Large selections may exceed short displays.
Dragged positions are not saved; **Show widgets** or
display changes reset placement. The medium card shows at most two providers,
although totals include all providers.

Provider log formats can change. Counts are activity estimates, not authoritative
process state. Panels are not WidgetKit extensions. See [accounting](pricing.md)
and [packaging](releasing.md).
