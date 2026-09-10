# UI workload measurements

Measured September 10, 2026 on macOS 26.5.2, Apple Silicon, native optimized build.
Run `just profile-ui` to repeat with isolated synthetic data; output is under
`build/profiling/`. No real provider logs or OS privacy changes are involved.

| Workload | Latest result |
| --- | --- |
| Import 20,000 synthetic usage events, verified in SQLite | 0.64 s wall time |
| Reopen unchanged logs and aggregate | 0.034 s wall time |
| Three visible cards, 14 snapshot changes over 70 s | 0.16 CPU seconds; 0.23% of one core |
| UI peak sampled RSS, after 5 s warm-up | 67.8 MiB |
| UI RSS change during measurement | −2.2 MiB |

A preceding run measured 0.83 s import and 0.11% UI CPU. These are individual local
runs, not statistically established speedups. RSS includes shared/resident pages;
it is not equivalent to macOS physical footprint.

The two-second stack sample showed the main thread waiting in the AppKit event
loop. A separate Instruments SwiftUI recording produced no SwiftUI data, so no
frame-time or hitch claim is made. GPU, battery impact, and multi-hour memory
behavior remain unmeasured.

`just refresh-smoke` checks actual AppState publications: immediate startup read,
changed data within the five-second polling interval (six-second test allowance),
and no publication on the next unchanged poll.

Layout checks cover all eight card selections, transparent corners across six
themes, and rendered overviews with 0, 1, 3, 5, and 8 agents. The overview displays
at most five rows and identifies additional agents without expanding the card.
