# Local telemetry protocol

Append newline-terminated JSON objects to a file under `$CATS_DATA_DIR/agents/`. Use stable, opaque session IDs and unique request IDs. Only publish metadata intended for display; never include prompts, messages, secrets, or source code.

```json
{"timestamp":"2026-09-09T12:00:00Z","session_id":"job-123","agent":"backend","status":"running"}
{"timestamp":"2026-09-09T12:01:00Z","session_id":"job-123","id":"request-1","agent":"backend","model":"local-model","status":"running","usage":{"input_tokens":1200,"output_tokens":300,"cache_read_input_tokens":100},"cost_usd":0.01}
{"timestamp":"2026-09-09T12:02:00Z","session_id":"job-123","agent":"backend","status":"completed"}
```

Status values: `running`, `waiting`, `failed`, `completed`. Emit lifecycle heartbeats every minute while running. Usage is per request, not cumulative. Input excludes cache reads/writes; optional cache fields follow Claude's schema. An explicit nonnegative finite `cost_usd` takes precedence over bundled model pricing. Without either, the usage is unpriced.

For pause/resume support, launch the agent with `cats run <name> -- <command>`. Metadata-only integrations are observed but cannot be controlled. The managed wrapper reads the shared `cats-control.json` desired state (`{"action":"pause"}` or `{"action":"resume"}`); the setting applies to all managed wrappers, including newly launched ones until resumed. A managed command's provider usage still appears in its provider session; V1 does not merge wrapper and provider identities.
