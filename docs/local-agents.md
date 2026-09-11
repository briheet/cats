# Local agents

## Report usage

Append newline-terminated JSON records to a `.jsonl` file in the configured data
directory's `agents/` folder. No HTTP service or SDK is required.

```json
{"timestamp":"2026-09-10T12:00:00Z","session_id":"job-1","agent":"backend","status":"running"}
{"timestamp":"2026-09-10T12:01:00Z","session_id":"job-1","agent":"backend","status":"running","id":"request-1","model":"local-model","usage":{"input_tokens":1200,"output_tokens":300},"cost_usd":0.01}
{"timestamp":"2026-09-10T12:02:00Z","session_id":"job-1","agent":"backend","status":"completed"}
```

- Every record needs an RFC 3339 `timestamp` and stable `session_id`.
- Status is `running`, `waiting`, `failed`, or `completed`. Send running heartbeats each minute.
- Usage records also need an `id` unique within the session. Usage is per request,
  not a session-wide cumulative counter.
- Input excludes cache tokens. Optional cache fields use Claude's schema:
  `cache_read_input_tokens`, `cache_creation_input_tokens`, and nested
  `cache_creation.ephemeral_1h_input_tokens`.
- A finite `cost_usd` from 0 through 1,000,000 overrides pricing. Without a valid
  explicit cost or known model, usage remains unpriced.
- A repeated request ID updates only when its total token count increases; this
  is not a general-purpose record editing API.

Do not include prompts, messages, secrets, or source code. Records larger than
1 MiB are skipped. Incomplete final lines are retried when more bytes arrive.

## Allow pause/resume

```sh
cats-llm run tests -- cargo test
```

The wrapper owns a subprocess group. Menu/dashboard controls suspend or resume
those groups only; existing Claude/Codex processes remain read-only. Use
noninteractive commands. Suspension does not cancel remote API work or guarantee
that billing stops.

`control.json` holds `{"action":"pause"}` or `{"action":"resume"}`.
This desired state applies to all wrappers, including new ones until resumed.
Wrapper identities and provider sessions are not merged, so one command can have
separate local lifecycle and provider usage entries.
