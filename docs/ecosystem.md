# Cats ecosystem

This is the current implementation reference. Historical `plan.md`, `design-plan.md`,
`implementation.md`, and `configuration-plan.md` describe earlier iterations;
their WidgetKit, compatibility, and single-product distribution notes do not apply.

## Ownership

| Product | Rust | Native Swift | Default storage |
| --- | --- | --- | --- |
| Cats LLM | `crates/cats-llm`: ingestion, SQLite, accounting, configuration | `macos/CatsApp`, `Shared`, `Views` | `~/Library/Application Support/CatsLLM` |
| Cats Metrics | `crates/cats-metrics`: sampling, bounded history, configuration | `macos/MetricsApp`, `MetricsShared` | `~/Library/Application Support/CatsMetrics` |

`cats-core` contains theme resolution and atomic private-file writes. `macos/UI`
contains visual primitives. SwiftPM combines the two model sets only for tests;
production targets compile independently. There is no shared runtime, database,
plugin host, IPC service, or network backend.

Each product writes `state.json`, `heartbeat`, and owns `collector.lock` in its
own directory. Their snapshot schemas are independent. LLM additionally owns
`usage.sqlite`, `control.json`, and managed-agent records. Metrics retains at most
60 CPU samples covering two minutes in memory and its current snapshot, not a history database.

## Metrics semantics

- CPU is total utilization normalized to 0–100%, not a sum across cores.
- Memory uses sysinfo's macOS used/total figures; swap is shown separately in the menu.
  This is not Activity Monitor's memory-pressure graph.
- Physical `en*` interfaces are sampled individually. The card shows the busiest;
  `network-interface` selects one explicitly, including a VPN tunnel. Interfaces
  are never summed, so tunnel and underlying traffic are not counted twice.
- Disk free space is the startup data volume (root fallback), not a sum of APFS
  volumes or an estimate of purgeable space.
- Battery and thermal state use public IOKit/Foundation APIs. Missing battery or
  unsupported values display a dash. Thermal state is qualitative, not Celsius.
- CPU/RAM/network sample every two seconds; battery/thermal every thirty seconds;
  disk every minute. Wake/clock discontinuities invalidate rate baselines and
  refresh slow readings. The next normal sample restores rates.
- CPU and network need a baseline: the first sample is unavailable, not zero.
  A missing/stale heartbeat (ten seconds) marks Metrics unavailable; invalid data
  preserves the last good reading. Denied storage access stops UI polling.

No sudo, Accessibility, screen recording, Wi-Fi location access, subprocess
polling, private hardware sensors, or cloud service is required by Metrics.
Rust uses sysinfo with selective features, plus narrow public macOS bindings.

## Presentation and lifecycle

Metrics has one 340 × 170 desktop card (bottom-left by default) and a menu popover
with swap and a two-minute CPU sparkline. LLM retains six card variants and its
dashboard. Both support shared themes and independent fonts/opacity. Panels are
behind normal windows and do not overlay fullscreen applications.

Home Manager owns separate collector/UI LaunchAgents for each product. Directly
launched bundles can start their own collector and stop only that owned child.
Starting a second collector for the same directory fails on the writer lock.

## Deliberate break

Use `cats-llm`, `cats-metrics`, `cats-llm-desktop`, and `cats-metrics-desktop`.
Configurations live under `~/.config/cats-llm` and `~/.config/cats-metrics`.
Environment prefixes are `CATS_LLM_` and `CATS_METRICS_`.
There are no old executable/option aliases, old-snapshot adapters, or automatic
migrations. Legacy installed apps/services are not stopped by repository checks;
retire them explicitly in your host configuration when deploying. Old data stays
untouched; LLM imports available provider logs into its new database.

Sources: [sysinfo](https://docs.rs/sysinfo/0.38.4/sysinfo/),
[Apple power-source descriptions](https://developer.apple.com/documentation/iokit/1523867-iopsgetpowersourcedescription),
[Apple thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum).
