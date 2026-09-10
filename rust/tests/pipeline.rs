use cats::collectors::{ClaudeParser, CodexParser, LocalParser, Parser};
use cats::domain::{AgentStatus, BudgetState, ProviderKind};
use cats::{
    aggregation::{State, aggregate_between},
    cli::Cli,
    collectors::{self, Cursor},
    snapshot,
    storage::Store,
    telemetry::{Event, Tokens, price},
};
use clap::Parser as _;
use serde_json::json;
use std::{fs, io::Write, path::Path};

#[test]
fn domain_values_preserve_json_and_sql_text() {
    let db = rusqlite::Connection::open_in_memory().unwrap();
    for (status, text) in [
        (AgentStatus::Unknown, ""),
        (AgentStatus::Running, "running"),
        (AgentStatus::Waiting, "waiting"),
        (AgentStatus::Completed, "completed"),
        (AgentStatus::Failed, "failed"),
        (AgentStatus::Idle, "idle"),
    ] {
        assert_eq!(serde_json::to_value(status).unwrap(), json!(text));
        assert_eq!(
            serde_json::from_value::<AgentStatus>(json!(text)).unwrap(),
            status
        );
        assert_eq!(
            db.query_row("SELECT ?1", [status], |row| row.get::<_, String>(0))
                .unwrap(),
            text
        );
        assert_eq!(
            db.query_row("SELECT ?1", [text], |row| row.get::<_, AgentStatus>(0))
                .unwrap(),
            status
        );
    }
    for provider in [
        ProviderKind::Claude,
        ProviderKind::Codex,
        ProviderKind::Local,
    ] {
        assert_eq!(
            serde_json::to_value(provider).unwrap(),
            json!(provider.as_str())
        );
        assert_eq!(
            db.query_row("SELECT ?1", [provider.as_str()], |row| row
                .get::<_, ProviderKind>(0))
                .unwrap(),
            provider
        );
    }
    let old_cursor = serde_json::to_value(Cursor::default()).unwrap();
    assert_eq!(old_cursor["status"], "");
    assert_eq!(
        serde_json::from_value::<Cursor>(old_cursor).unwrap().status,
        AgentStatus::Unknown
    );
    assert!(serde_json::from_value::<AgentStatus>(json!("bogus")).is_err());
    assert!(
        db.query_row("SELECT 'bogus'", [], |row| row.get::<_, ProviderKind>(0))
            .is_err()
    );
}

#[test]
fn parser_implementations_validate_timestamps_and_ignore_unknown_records() {
    for parser in [&CodexParser as &dyn Parser, &ClaudeParser, &LocalParser] {
        let mut cursor = Cursor::default();
        assert!(parser.parse(&json!({}), &mut cursor).is_none());
        assert!(parser.parse(&json!({"timestamp":"2099-01-01T00:00:00Z", "type":"event_msg", "payload":{"type":"task_started"}}), &mut cursor).is_none());
        assert_eq!(cursor.updated, 0);
    }
    let mut cursor = Cursor::default();
    assert!(CodexParser.parse(&json!({"timestamp":"2026-01-01T00:00:00Z", "type":"event_msg", "payload":{"type":"future_event"}}), &mut cursor).is_none());
    assert_eq!(cursor.status, AgentStatus::Unknown);
}
#[test]
fn aggregation_rejects_invalid_budgets() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(&directory.path().join("test.sqlite")).unwrap();
    for budget in [0., -1., f64::NAN, f64::INFINITY] {
        assert!(aggregate_between(&store, 1000, 0, 86400, budget).is_err());
    }
}

#[test]
fn legacy_app_group_never_selects_protected_storage() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("config.toml");
    fs::write(&file, "").unwrap();
    let invoke = |group: &str| {
        std::process::Command::new(env!("CARGO_BIN_EXE_cats"))
            .args(["--config", file.to_str().unwrap(), "config"])
            .env("HOME", dir.path())
            .env("CATS_APP_GROUP", group)
            .env_remove("CATS_DATA_DIR")
            .env_remove("CATS_BUDGET_USD")
            .output()
            .unwrap()
    };
    let output = invoke("ABCDE12345.dev.cats.shared");
    assert!(output.status.success());
    let config: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        config["data_dir"],
        dir.path()
            .join("Library/Application Support/Cats")
            .to_str()
            .unwrap()
    );
    assert!(!dir.path().join("Library").exists());
    for group in ["", "group.dev.cats.shared", "../escape", ".."] {
        let output = invoke(group);
        assert!(output.status.success());
        let config: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(
            config["data_dir"],
            dir.path()
                .join("Library/Application Support/Cats")
                .to_str()
                .unwrap()
        );
    }
}

#[test]
fn scanning_does_not_swallow_permission_denials() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o0)).unwrap();
    let result = collectors::files(dir.path());
    fs::set_permissions(dir.path(), fs::Permissions::from_mode(0o700)).unwrap();
    assert_eq!(
        result.unwrap_err().kind(),
        std::io::ErrorKind::PermissionDenied
    );
    assert!(
        collectors::files(&dir.path().join("missing"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn themes_resolve_inheritance_and_reject_invalid_inputs() {
    use cats::theme::{Appearance, BUILTINS, resolve};
    let dir = tempfile::tempdir().unwrap();
    for (name, _) in BUILTINS {
        resolve(name, dir.path()).unwrap();
    }
    let dawn = resolve("rose-pine-dawn", dir.path()).unwrap();
    assert_eq!(dawn.appearance, Appearance::Light);
    assert_eq!(dawn.colors["surface"], "#faf4ed");
    fs::write(
        dir.path().join("custom.toml"),
        "inherits = 'nord'\n[colors]\naccent = '#abcdef'",
    )
    .unwrap();
    let custom = resolve("custom", dir.path()).unwrap();
    assert_eq!(custom.colors["accent"], "#abcdef");
    assert_eq!(custom.colors["surface"], "#2e3440");
    for text in [
        "inherits = 'custom'",
        "[colors]\naccent = 'red'",
        "[colors]\nacccent = '#ffffff'",
        "unknown = true",
    ] {
        fs::write(dir.path().join("custom.toml"), text).unwrap();
        assert!(resolve("custom", dir.path()).is_err());
    }
    assert!(resolve("../nord", dir.path()).is_err());
    assert!(resolve("missing", dir.path()).is_err());
}

#[test]
fn configuration_is_strict_and_cli_overrides_file() {
    use cats::config::Config;
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("config.toml");
    assert!(Config::load(Some(file.clone()), None, None).is_err());
    fs::write(
        &file,
        "theme = 'nord'\nbudget-usd = 40\nclaude-dir = '~/test/projects'",
    )
    .unwrap();
    let config =
        Config::load(Some(file.clone()), Some(dir.path().join("data")), Some(12.)).unwrap();
    assert_eq!(config.budget_usd, 12.);
    assert_eq!(config.data_dir, dir.path().join("data"));
    assert!(config.claude_dir.is_absolute());
    assert_eq!(config.theme.colors["surface"], "#2e3440");
    assert_eq!(
        Config::load(Some(file.clone()), None, None)
            .unwrap()
            .budget_usd,
        40.
    );
    assert!(!dir.path().join("data").exists());
    for text in [
        "budget-usd = nan",
        "budget-usd = 0",
        "buget-usd = 2",
        "data-dir = 'relative'",
        "theme = 'missing'",
    ] {
        fs::write(&file, text).unwrap();
        assert!(Config::load(Some(file.clone()), None, None).is_err());
    }
}

fn store() -> Store {
    Store::open(Path::new(":memory:")).unwrap()
}
fn parse_fixture(text: &str, provider: ProviderKind) -> (Cursor, Vec<Event>) {
    let mut cursor = Cursor::default();
    let events = text
        .lines()
        .filter_map(|line| {
            collectors::parse(&serde_json::from_str(line).unwrap(), provider, &mut cursor)
        })
        .collect();
    (cursor, events)
}
fn event(id: &str, timestamp: i64, cost: f64) -> Event {
    Event {
        id: id.into(),
        timestamp,
        provider: ProviderKind::Claude,
        model: "claude-sonnet-4-6".into(),
        session: "s".into(),
        agent: "s".into(),
        tokens: Tokens {
            input: 1000,
            ..Tokens::default()
        },
        cost: Some(cost),
    }
}

#[test]
fn claude_cache_buckets_are_disjoint() {
    let (c, events) = parse_fixture(include_str!("fixtures/claude.jsonl"), ProviderKind::Claude);
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].tokens.total(), 2100);
    assert_eq!(events[0].tokens.cache_write, 300);
    assert_eq!(events[0].tokens.cache_write_1h, 100);
    assert!((events[0].cost.unwrap() - 0.007875).abs() < 1e-10);
    assert_eq!(c.status, AgentStatus::Completed);
    assert_eq!(c.name, "backend");
}
#[test]
fn codex_cumulative_usage_deduplicates_and_excludes_reasoning_subtotal() {
    let (c, events) = parse_fixture(include_str!("fixtures/codex.jsonl"), ProviderKind::Codex);
    assert_eq!(events.len(), 2);
    assert_eq!(events.iter().map(|e| e.tokens.total()).sum::<u64>(), 1750);
    assert_eq!(events[1].tokens.input, 500);
    assert_eq!(c.status, AgentStatus::Waiting);
}
#[test]
fn unknown_models_are_unpriced_and_version_matching_is_exact() {
    let t = Tokens {
        input: 1_000_000,
        ..Tokens::default()
    };
    assert_eq!(price("future-model", t), None);
    assert_eq!(price("claude-sonnet-4-20250514", t), Some(3.));
    assert_eq!(price("claude-sonnet-4-99", t), None);
    assert_eq!(price("gpt-5.6-sol", t), Some(4.));
}
#[test]
fn invalid_input_and_future_events_are_ignored() {
    let mut c = Cursor::default();
    assert!(collectors::parse(&json!({}), ProviderKind::Claude, &mut c).is_none());
    assert!(
        collectors::parse(
            &json!({"timestamp":"2099-01-01T00:00:00Z"}),
            ProviderKind::Local,
            &mut c
        )
        .is_none()
    );
    assert_eq!(
        Tokens::codex(&json!({"input_tokens":10,"cached_input_tokens":100,"output_tokens":-3}))
            .total(),
        10
    );
}
#[test]
fn sqlite_migration_is_repeatable_and_usage_upserts() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("db");
    let s = Store::open(&path).unwrap();
    let mut e = event("a", 100, 1.);
    assert_eq!(Store::insert(s.connection(), &e).unwrap(), 1);
    assert_eq!(Store::insert(s.connection(), &e).unwrap(), 0);
    e.tokens.output = 100;
    e.cost = Some(2.);
    assert_eq!(Store::insert(s.connection(), &e).unwrap(), 1);
    drop(s);
    let s = Store::open(&path).unwrap();
    let total: f64 = s
        .connection()
        .query_row("SELECT SUM(cost) FROM events", [], |r| r.get(0))
        .unwrap();
    assert_eq!(total, 2.);
}
#[test]
fn incremental_ingestion_survives_restart_rotation_and_partial_lines() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("session.jsonl");
    let db = dir.path().join("db");
    fs::write(&path, include_str!("fixtures/codex.jsonl")).unwrap();
    let mut s = Store::open(&db).unwrap();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Codex)
            .unwrap()
            .events,
        2
    );
    drop(s);
    let mut s = Store::open(&db).unwrap();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Codex)
            .unwrap()
            .events,
        0
    );
    let extra = json!({"timestamp":"2026-09-09T12:20:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"cached_input_tokens":500,"output_tokens":200}}}}).to_string();
    let mut file = fs::OpenOptions::new().append(true).open(&path).unwrap();
    write!(file, "{extra}").unwrap();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Codex)
            .unwrap()
            .events,
        0
    );
    writeln!(file).unwrap();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Codex)
            .unwrap()
            .events,
        1
    );
    fs::rename(&path, dir.path().join("old")).unwrap();
    fs::write(&path, include_str!("fixtures/codex.jsonl")).unwrap();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Codex)
            .unwrap()
            .events,
        0
    );
    assert_eq!(
        s.connection()
            .query_row("SELECT COUNT(*) FROM events", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        3
    );
}
#[test]
fn malformed_and_oversized_lines_do_not_block_valid_records() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("claude.jsonl");
    let content = format!(
        "invalid\n{}\n{}",
        "x".repeat(1_100_000),
        include_str!("fixtures/claude.jsonl")
    );
    fs::write(&path, content).unwrap();
    let mut s = store();
    assert_eq!(
        collectors::ingest(&mut s, &path, ProviderKind::Claude)
            .unwrap()
            .events,
        1
    );
}
#[test]
fn daily_totals_rolling_burn_and_projection_have_separate_windows() {
    let s = store();
    for (id, ts, cost) in [
        ("old", 100, 10.),
        ("a", 8000, 1.),
        ("b", 8500, 2.),
        ("future", 9500, 99.),
    ] {
        Store::insert(s.connection(), &event(id, ts, cost)).unwrap();
    }
    let result = aggregate_between(&s, 9000, 7200, 93600, 20.).unwrap();
    assert_eq!(result.today.spend_usd, 3.);
    assert_eq!(result.today.burn_rate_per_hour, 6.);
    assert_eq!(result.today.projected_daily_spend, Some(144.));
    assert_eq!(result.today.tokens_total, 2000);
    assert_eq!(result.today.budget_state, BudgetState::Normal);
}
#[test]
fn projection_requires_history_and_known_prices() {
    let s = store();
    Store::insert(s.connection(), &event("a", 8900, 19.)).unwrap();
    let result = aggregate_between(&s, 9000, 0, 86400, 20.).unwrap();
    assert!(result.today.projected_daily_spend.is_none());
    assert_eq!(result.today.budget_state, BudgetState::Warning);
    let mut e = event("b", 8000, 2.);
    e.cost = None;
    Store::insert(s.connection(), &e).unwrap();
    assert_eq!(
        aggregate_between(&s, 9000, 0, 86400, 20.)
            .unwrap()
            .today
            .unpriced_events,
        1
    );
}
#[test]
fn idle_agents_wait_instead_of_falsely_completing() {
    let s = store();
    let c = Cursor {
        session: "s".into(),
        name: "backend".into(),
        status: AgentStatus::Running,
        started: 8000,
        updated: 8100,
        ..Cursor::default()
    };
    Store::save_cursor(s.connection(), "test", ProviderKind::Claude, &c).unwrap();
    assert_eq!(
        aggregate_between(&s, 8200, 0, 86400, 20.)
            .unwrap()
            .active_agents,
        1
    );
    assert_eq!(
        aggregate_between(&s, 9000, 0, 86400, 20.)
            .unwrap()
            .waiting_agents,
        1
    );
}
#[test]
fn snapshots_are_atomic_and_only_rewrite_changed_content() {
    let dir = tempfile::tempdir().unwrap();
    let mut state = aggregate_between(&store(), 9000, 0, 86400, 20.).unwrap();
    assert!(snapshot::write(dir.path(), &state).unwrap());
    state.generated_at += 60;
    assert!(!snapshot::write(dir.path(), &state).unwrap());
    let value: State =
        serde_json::from_slice(&fs::read(dir.path().join("cats-state.json")).unwrap()).unwrap();
    assert_eq!(value.generated_at, 9000);
    assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
}

#[test]
fn agent_activity_is_not_turn_duration_and_unknown_starts_stay_unknown() {
    let s = store();
    let mut cursor = Cursor {
        session: "old-turn".into(),
        status: AgentStatus::Completed,
        started: 8000,
        updated: 8482,
        ..Cursor::default()
    };
    Store::save_cursor(s.connection(), "old-turn", ProviderKind::Codex, &cursor).unwrap();
    let state = aggregate_between(&s, 44000, 0, 86400, 20.).unwrap();
    assert_eq!(state.agents[0].elapsed_seconds, 482);
    assert_eq!(state.agents[0].last_activity_at, Some(8482));
    assert_eq!(state.agents[0].status, AgentStatus::Idle);
    cursor.started = 0;
    cursor.status = AgentStatus::Running;
    Store::save_cursor(s.connection(), "old-turn", ProviderKind::Codex, &cursor).unwrap();
    let state = aggregate_between(&s, 44000, 0, 86400, 20.).unwrap();
    assert_eq!(state.agents[0].elapsed_seconds, 0);
    assert_eq!(state.agents[0].status, AgentStatus::Idle);
    assert_eq!(state.waiting_agents, 0);
    assert!(
        aggregate_between(&s, 8400, 0, 86400, 20.)
            .unwrap()
            .agents
            .is_empty()
    );
    assert_eq!(
        AgentStatus::Running.at(ProviderKind::Local, 3600),
        AgentStatus::Waiting
    );
}

#[test]
fn codex_turn_completion_waits_then_idles_and_can_resume() {
    let s = store();
    let mut cursor = Cursor {
        session: "conversation".into(),
        ..Cursor::default()
    };
    for (kind, timestamp, status) in [
        ("task_started", 8000, AgentStatus::Running),
        ("task_complete", 8100, AgentStatus::Waiting),
        ("task_started", 8200, AgentStatus::Running),
    ] {
        let value = json!({
            "timestamp": chrono::DateTime::from_timestamp(timestamp, 0).unwrap().to_rfc3339(),
            "type": "event_msg", "payload": { "type": kind }
        });
        assert!(collectors::parse(&value, ProviderKind::Codex, &mut cursor).is_none());
        assert_eq!(cursor.status, status);
        Store::save_cursor(s.connection(), "conversation", ProviderKind::Codex, &cursor).unwrap();
        let state = aggregate_between(&s, timestamp, 0, 86400, 20.).unwrap();
        assert_eq!(
            state.active_agents,
            u64::from(status == AgentStatus::Running)
        );
        assert_eq!(
            state.waiting_agents,
            u64::from(status == AgentStatus::Waiting)
        );
    }
    for status in [AgentStatus::Waiting, AgentStatus::Completed] {
        cursor.status = status;
        Store::save_cursor(s.connection(), "conversation", ProviderKind::Codex, &cursor).unwrap();
        assert_eq!(
            aggregate_between(&s, 8300, 0, 86400, 20.)
                .unwrap()
                .waiting_agents,
            1
        );
        let idle = aggregate_between(&s, 8501, 0, 86400, 20.).unwrap();
        assert_eq!(idle.waiting_agents, 0);
        assert_eq!(idle.agents[0].status, AgentStatus::Idle);
    }
}
#[test]
fn storage_never_retains_conversation_content() {
    let (c, events) = parse_fixture(include_str!("fixtures/claude.jsonl"), ProviderKind::Claude);
    let s = store();
    for e in events {
        Store::insert(s.connection(), &e).unwrap();
    }
    Store::save_cursor(s.connection(), "source", ProviderKind::Claude, &c).unwrap();
    let names: String = s
        .connection()
        .query_row(
            "SELECT GROUP_CONCAT(name) FROM pragma_table_info('events')",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(!names.contains("content") && !names.contains("prompt"));
    assert!(!serde_json::to_string(&c).unwrap().contains("message"));
}
#[test]
fn clap_validates_budget_and_preserves_agent_arguments() {
    assert!(Cli::try_parse_from(["cats", "--budget", "NaN"]).is_err());
    assert!(Cli::try_parse_from(["cats", "--budget", "0"]).is_err());
    assert!(Cli::try_parse_from(["cats", "run", "backend", "--", "echo", "--hello"]).is_ok());
    assert!(Cli::try_parse_from(["cats", "run", "backend"]).is_err());
}
