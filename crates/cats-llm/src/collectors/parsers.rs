//! Provider-specific JSONL decoding. Only usage and lifecycle metadata are retained.
use super::Cursor;
use crate::domain::{AgentStatus, ProviderKind};
use crate::telemetry::{Event, Tokens, label, price};
use chrono::DateTime;
use serde::Deserialize;
use serde_json::Value;
use std::path::Path;

/// Provider parsers share timestamp validation and retain only telemetry metadata.
pub trait Parser {
    fn parse_record(&self, value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event>;

    fn parse(&self, value: &Value, cursor: &mut Cursor) -> Option<Event> {
        let timestamp = DateTime::parse_from_rfc3339(value["timestamp"].as_str()?)
            .ok()?
            .timestamp();
        if timestamp < 0 || timestamp > chrono::Utc::now().timestamp() + 300 {
            return None;
        }
        self.parse_record(value, cursor, timestamp)
    }
}

pub struct CodexParser;
pub struct ClaudeParser;
pub struct LocalParser;

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
enum RecordKind {
    SessionMeta,
    TurnContext,
    EventMsg,
    User,
    Assistant,
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum CodexEventKind {
    TaskStarted,
    TaskComplete,
    TurnAborted,
    Error,
    TokenCount,
    #[serde(other)]
    Other,
}

pub fn parse(value: &Value, provider: ProviderKind, cursor: &mut Cursor) -> Option<Event> {
    match provider {
        ProviderKind::Codex => CodexParser.parse(value, cursor),
        ProviderKind::Claude => ClaudeParser.parse(value, cursor),
        ProviderKind::Local => LocalParser.parse(value, cursor),
    }
}

impl Parser for CodexParser {
    fn parse_record(&self, value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
        let provider = ProviderKind::Codex;
        let kind = serde_json::from_value::<RecordKind>(value["type"].clone())
            .unwrap_or(RecordKind::Other);
        let payload = &value["payload"];
        if kind == RecordKind::SessionMeta {
            cursor.session = label(
                payload["id"]
                    .as_str()
                    .or(payload["session_id"].as_str())
                    .unwrap_or(&cursor.session),
            );
            cursor.name = project(&payload["cwd"]);
        }
        if kind == RecordKind::TurnContext {
            cursor.model = label(payload["model"].as_str().unwrap_or("unknown"));
        }
        if kind != RecordKind::EventMsg {
            return None;
        }
        match serde_json::from_value::<CodexEventKind>(payload["type"].clone())
            .unwrap_or(CodexEventKind::Other)
        {
            CodexEventKind::TaskStarted => {
                cursor.started = timestamp;
                cursor.status = AgentStatus::Running;
                cursor.updated = timestamp;
            }
            CodexEventKind::TaskComplete => {
                // A turn ended; the conversation can still accept another prompt.
                cursor.status = AgentStatus::Waiting;
                cursor.updated = timestamp;
            }
            CodexEventKind::TurnAborted | CodexEventKind::Error => {
                cursor.status = AgentStatus::Failed;
                cursor.updated = timestamp;
            }
            CodexEventKind::TokenCount => {
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
                        cursor.session,
                        total.input,
                        total.output,
                        total.cache_read,
                        total.cache_write
                    ),
                    delta,
                ));
            }
            _ => (),
        }
        None
    }
}

impl Parser for ClaudeParser {
    fn parse_record(&self, value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
        let provider = ProviderKind::Claude;
        let kind = serde_json::from_value::<RecordKind>(value["type"].clone())
            .unwrap_or(RecordKind::Other);
        if let Some(id) = value["sessionId"].as_str() {
            cursor.session = label(id);
        }
        if value["cwd"].is_string() {
            cursor.name = project(&value["cwd"]);
        }
        if kind == RecordKind::User {
            cursor.started = timestamp;
            cursor.updated = timestamp;
            cursor.status = AgentStatus::Running;
        }
        if kind != RecordKind::Assistant {
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
            AgentStatus::Failed
        } else if message["stop_reason"].as_str() == Some("end_turn") {
            AgentStatus::Completed
        } else {
            AgentStatus::Running
        };
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
}

impl Parser for LocalParser {
    fn parse_record(&self, value: &Value, cursor: &mut Cursor, timestamp: i64) -> Option<Event> {
        let provider = ProviderKind::Local;
        cursor.session = label(value["session_id"].as_str()?);
        cursor.name = label(value["agent"].as_str().unwrap_or("Local agent"));
        cursor.model = label(value["model"].as_str().unwrap_or("local"));
        let status = serde_json::from_value::<AgentStatus>(value["status"].clone())
            .ok()
            .filter(|status| {
                matches!(
                    status,
                    AgentStatus::Running
                        | AgentStatus::Waiting
                        | AgentStatus::Completed
                        | AgentStatus::Failed
                )
            })
            .unwrap_or(AgentStatus::Waiting);
        if cursor.started == 0
            || status == AgentStatus::Running && cursor.status == AgentStatus::Completed
        {
            cursor.started = timestamp;
        }
        cursor.updated = timestamp;
        cursor.status = status;
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
}

fn project(value: &Value) -> String {
    label(
        Path::new(value.as_str().unwrap_or(""))
            .file_name()
            .and_then(|x| x.to_str())
            .unwrap_or("Agent"),
    )
}
fn event(
    cursor: &Cursor,
    provider: ProviderKind,
    timestamp: i64,
    id: String,
    tokens: Tokens,
) -> Event {
    Event {
        id,
        timestamp,
        provider,
        model: cursor.model.clone(),
        session: cursor.session.clone(),
        agent: cursor.session.clone(),
        tokens,
        cost: price(&cursor.model, tokens),
    }
}
