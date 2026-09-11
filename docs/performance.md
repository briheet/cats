# UI workload measurements

## Independent products (September 11, 2026)

`just profile-ecosystem` ran optimized Apple Silicon binaries for 70.69 seconds
after a three-second warm-up. LLM used isolated provider fixtures and its default
large/medium cards; Metrics sampled the local system with its overview card.
Both used Nord. There were 34 observed metrics snapshot changes; LLM storage
remained unchanged, duplicate metrics writers were rejected, and no metrics
database was created. All test-owned processes were stopped afterward.

| Process | CPU (% of one core) | Peak sampled RSS |
| --- | --- | --- |
| Metrics collector | 0.13% | 10.6 MiB |
| Metrics UI | 0.18% | 52.7 MiB |
| LLM UI | 0.13% | 65.2 MiB |

This is one bounded run, not a battery-efficiency or multi-hour memory guarantee.
Other builds were running concurrently; window occlusion was uncontrolled. RSS
is not physical footprint. The script records its report in
`build/ecosystem-report.json`. `just metrics-refresh-smoke` separately verifies
startup reads, two-second publications, unchanged-state suppression and retention
of the last good reading after corruption.

## Earlier single-product measurements

Measured September 10, 2026 on macOS 26.5.2, Apple Silicon, native optimized build.
Run `just profile-ui` to repeat with isolated synthetic data; output is under
`build/profiling/`. No real provider logs or OS privacy changes are involved.

| Workload | Latest result |
| --- | --- |
| Import 20,000 synthetic usage events, verified in SQLite | 0.93 s wall time |
| Reopen unchanged logs and aggregate | 0.032 s wall time |
| Six configured cards, 14 snapshot changes over 70 s | 0.09 CPU seconds; 0.13% of one core |
| UI peak sampled RSS, after 5 s warm-up | 74.6 MiB |
| UI RSS change during measurement | −2.8 MiB |

Set `CATS_LLM_WIDGETS=large,medium,medium-agents,small,small-agents,small-burn-rate`
when running `just profile-ui` to reproduce the six-card configuration. The harness
does not control window occlusion, so CPU is not a worst-case rendering bound.

A preceding three-card run measured 0.64 s import and 0.23% UI CPU. These are individual local
runs, not statistically established speedups. RSS includes shared/resident pages;
it is not equivalent to macOS physical footprint.

After the activity-age fix, a three-card run (`just profile-ui`) verified 20,000
events in 0.81 s, reopened unchanged logs in 0.031 s, and used 0.08 CPU seconds
over 70.1 s (0.11% of one core). Peak sampled RSS was 70.3 MiB, growing 80 KiB.
This workload uses synthetic legacy snapshots without activity timestamps;
timestamp labels are exercised separately by formatter tests and rendered previews.

The two-second stack sample showed the main thread waiting in the AppKit event
loop. A separate Instruments SwiftUI recording produced no SwiftUI data, so no
frame-time or hitch claim is made. GPU, battery impact, and multi-hour memory
behavior remain unmeasured.

`just refresh-smoke` checks actual AppState publications: immediate startup read,
changed data within the five-second polling interval (six-second test allowance),
and no publication on the next unchanged poll.

Rendered layout checks cover all 64 card selections, transparent corners across six
themes, and rendered overviews with 0, 1, 3, 5, and 8 agents. The overview displays
at most five rows and identifies additional agents without expanding the card.

A repeat live-window smoke check reported 334 × 168 from WindowServer for a
medium panel whose AppKit frame was 340 × 170. The strict geometry check remains
failing in that desktop state; rendered sizes pass. Display transforms are not
controlled by the harness.
