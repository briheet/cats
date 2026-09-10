# Accounting and activity

## Spend is an estimate

Cats multiplies recorded token counts by its bundled API rates. This estimates
the API-equivalent cost of observed work; it does not read your provider bill.

Implemented models and rates live in [`price()`](../rust/src/telemetry.rs).
Unknown models keep their token counts but have no cost. Their usage is excluded
from monetary totals and produces a partial-estimate warning. Valid explicit
local-agent costs override model pricing.

Subscriptions, remaining quota, discounts, taxes, tool fees, priority tiers, and
long-context premiums are not modeled. Rates are applied during ingestion, not
looked up by event date. Updating rates does not automatically reprice stored history.

## Token accounting

Input, output, cache reads, short cache writes, and one-hour cache writes are
separate buckets. Cost is the sum of each bucket multiplied by its rate.

- Codex cumulative usage becomes deltas. Cached input is removed from regular
  input; reasoning output is not added again.
- Claude usage is per message. Growing message records replace smaller totals.
- Implemented cache-write multipliers are 1.25× input for short writes and 2×
  for one-hour writes.

## Time windows

| Display | Calculation |
| --- | --- |
| Spend/tokens today | Events since local midnight |
| Provider totals | Today's events grouped by provider |
| Agent spend/tokens | Matching session events, not just today's events |
| Burn rate | Spend over the trailing 30 minutes × 2 |
| Projected daily spend | Spend today + burn rate × hours until local midnight |

Projection requires two or more priced events spanning five minutes in the trailing
window, and no unpriced events today. It assumes the recent rate continues; it is
not a forecast of scheduled work. The sparkline shows 12 hourly buckets.

## Running, waiting, idle

Counts are inferred from logs, not process inspection. Codex `task_started` marks
a turn running. `task_complete` marks it waiting for five minutes, then idle.
Older stored Codex completions use the same rule. Aborted/error turns are failed.

Any running record silent for over five minutes is displayed as waiting, not
assumed finished. Claude/Codex running or waiting records silent for over 30 minutes
become idle, so abandoned sessions do not wait forever. Claude end-turn records are completed. Local agents report their
own status and should emit a heartbeat each minute while running.

The UI reads every five seconds, so counts can briefly lag a new turn. No usage is different
from unavailable collection: a separate collector heartbeat determines health,
not the age of the spend snapshot.

Agent-row times mean **time since last logged activity**, with an explicit `ago`
suffix. They are not turn durations or proof that a process is still open. Age
labels refresh once per minute even if the snapshot is unchanged. Missing activity
timestamps display a dash; unknown start times do not become fabricated runtimes.
