//! Provider-specific JSONL decoding. Only usage and lifecycle metadata are retained.
use super::Cursor;
use crate::telemetry::{Event, Tokens, label, price};
use chrono::DateTime;
use serde_json::Value;
use std::path::Path;

pub fn parse(value: &Value, provider: &str, cursor: &mut Cursor) -> Option<Event> {
    let timestamp = DateTime::parse_from_rfc3339(value["timestamp"].as_str()?)
        .ok()?
        .timestamp();
    if timestamp < 0 || timestamp > chrono::Utc::now().timestamp() + 300 {
        return None;
    }
    match provider {
        "Codex" => parse_codex(value, cursor, timestamp),
        "Claude" => parse_claude(value, cursor, timestamp),
        "Local" => parse_local(value, cursor, timestamp),
        _ => None,
    }
}

fn parse_codex(value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
    let provider = "Codex";
    let kind = value["type"].as_str().unwrap_or("");
    let payload = &value["payload"];
    if kind == "session_meta" {
        cursor.session = label(
            payload["id"]
                .as_str()
                .or(payload["session_id"].as_str())
                .unwrap_or(&cursor.session),
        );
        cursor.name = project(&payload["cwd"]);
    }
    if kind == "turn_context" {
        cursor.model = label(payload["model"].as_str().unwrap_or("unknown"));
    }
    if kind != "event_msg" {
        return None;
    }
    match payload["type"].as_str().unwrap_or("") {
        "task_started" => {
            cursor.started = timestamp;
            cursor.status = "running".into();
            cursor.updated = timestamp;
        }
        "task_complete" => {
            cursor.status = "completed".into();
            cursor.updated = timestamp;
        }
        "turn_aborted" | "error" => {
            cursor.status = "failed".into();
            cursor.updated = timestamp;
        }
        "token_count" => {
            let usage = &payload["info"]["total_token_usage"];
            if !usage.is_object() {
                return None;
            }
            let total = Tokens::codex(usage);
            let delta = total.delta(cursor.total);
            cursor.total = total;
            if delta.total() == 0 {
                return None;
            }
            cursor.updated = timestamp;
            return Some(event(
                cursor,
                provider,
                timestamp,
                format!(
                    "{}:{timestamp}:{}:{}:{}:{}",
                    cursor.session, total.input, total.output, total.cache_read, total.cache_write
                ),
                delta,
            ));
        }
        _ => (),
    }
    None
}

fn parse_claude(value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
    let provider = "Claude";
    let kind = value["type"].as_str().unwrap_or("");
    if let Some(id) = value["sessionId"].as_str() {
        cursor.session = label(id);
    }
    if value["cwd"].is_string() {
        cursor.name = project(&value["cwd"]);
    }
    if kind == "user" {
        cursor.started = timestamp;
        cursor.updated = timestamp;
        cursor.status = "running".into();
    }
    if kind != "assistant" {
        return None;
    }
    let message = &value["message"];
    if !message["usage"].is_object() {
        return None;
    }
    cursor.model = label(message["model"].as_str().unwrap_or("unknown"));
    cursor.updated = timestamp;
    if cursor.started == 0 {
        cursor.started = timestamp;
    }
    cursor.status = if value["isApiErrorMessage"].as_bool() == Some(true) {
        "failed"
    } else if message["stop_reason"].as_str() == Some("end_turn") {
        "completed"
    } else {
        "running"
    }
    .into();
    let id = format!(
        "{}:{}",
        cursor.session,
        message["id"].as_str().or(value["uuid"].as_str())?
    );
    Some(event(
        cursor,
        provider,
        timestamp,
        id,
        Tokens::claude(&message["usage"]),
    ))
}

fn parse_local(value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
    let provider = "Local";
    cursor.session = label(value["session_id"].as_str()?);
    cursor.name = label(value["agent"].as_str().unwrap_or("Local agent"));
    cursor.model = label(value["model"].as_str().unwrap_or("local"));
    if cursor.started == 0
        || value["status"].as_str() == Some("running") && cursor.status == "completed"
    {
        cursor.started = timestamp;
    }
    cursor.updated = timestamp;
    cursor.status = match value["status"].as_str().unwrap_or("waiting") {
        "running" => "running",
        "completed" => "completed",
        "failed" => "failed",
        _ => "waiting",
    }
    .into();
    if !value["usage"].is_object() {
        return None;
    }
    let mut record = event(
        cursor,
        provider,
        timestamp,
        format!("{}:{}", cursor.session, value["id"].as_str()?),
        Tokens::claude(&value["usage"]),
    );
    record.cost = value["cost_usd"]
        .as_f64()
        .filter(|x| x.is_finite() && *x >= 0. && *x <= 1_000_000.)
        .or(record.cost);
    Some(record)
}

fn project(value: &Value) -> String {
    label(
        Path::new(value.as_str().unwrap_or(""))
            .file_name()
            .and_then(|x| x.to_str())
            .unwrap_or("Agent"),
    )
}
fn event(cursor: &Cursor, provider: &str, timestamp: i64, id: String, tokens: Tokens) -> Event {
    Event {
        id,
        timestamp,
        provider: provider.into(),
        model: cursor.model.clone(),
        session: cursor.session.clone(),
        agent: cursor.session.clone(),
        tokens,
        cost: price(&cursor.model, tokens),
    }
}
