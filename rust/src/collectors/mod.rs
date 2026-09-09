use crate::{
    Result,
    storage::Store,
    telemetry::{Event, Tokens, label, price},
};
use chrono::DateTime;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs::{self, File},
    io::{BufRead, BufReader, Read, Seek, SeekFrom},
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};

#[derive(Clone, Default, Debug, Deserialize, Serialize)]
pub struct Cursor {
    pub offset: u64,
    pub inode: u64,
    pub session: String,
    pub model: String,
    pub name: String,
    pub total: Tokens,
    pub started: i64,
    pub updated: i64,
    pub status: String,
    pub skipping: bool,
}

pub fn files(root: &Path) -> Vec<PathBuf> {
    let mut result = Vec::new();
    let mut dirs = vec![root.to_path_buf()];
    while let Some(dir) = dirs.pop() {
        let Ok(entries) = fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if kind.is_dir() {
                dirs.push(entry.path());
            } else if kind.is_file() && entry.path().extension().is_some_and(|x| x == "jsonl") {
                result.push(entry.path());
            }
        }
    }
    result.sort();
    result
}

#[derive(Debug, Default)]
pub struct Batch {
    pub events: usize,
    pub more: bool,
}

pub fn ingest(store: &mut Store, path: &Path, provider: &str) -> Result<Batch> {
    let file = File::open(path)?;
    let meta = file.metadata()?;
    let key = path.to_string_lossy();
    let mut c = store.cursor(&key)?;
    if c.inode != meta.ino() || meta.len() < c.offset {
        c = Cursor::default();
    }
    c.inode = meta.ino();
    if c.offset == meta.len() {
        return Ok(Batch::default());
    }
    if c.session.is_empty() {
        c.session = label(
            path.file_stem()
                .and_then(|x| x.to_str())
                .unwrap_or("session"),
        );
    }
    let mut reader = BufReader::new(file);
    reader.seek(SeekFrom::Start(c.offset))?;
    let tx = store.db.transaction()?;
    let mut count = 0;
    let mut bytes = 0;
    // Bound memory even when logs contain enormous prompts or malformed lines.
    while bytes < 4 * 1_048_576 {
        let mut line = Vec::new();
        let n = reader
            .by_ref()
            .take(1_048_576)
            .read_until(b'\n', &mut line)?;
        if n == 0 {
            break;
        }
        let complete = line.last() == Some(&b'\n');
        if !complete && n < 1_048_576 {
            break;
        } // retry a partially appended line later
        c.offset += n as u64;
        bytes += n;
        if !complete {
            c.skipping = true;
            continue;
        }
        if c.skipping {
            c.skipping = false;
            continue;
        }
        match serde_json::from_slice::<Value>(&line) {
            Ok(v) => {
                if let Some(e) = parse(&v, provider, &mut c) {
                    count += Store::insert(&tx, &e)?;
                }
            }
            Err(_) => tracing::warn!(collector = provider, "Skipped malformed telemetry record"),
        }
        if bytes >= 4 * 1_048_576 {
            break;
        }
    }
    Store::save_cursor(&tx, &key, provider, &c)?;
    tx.commit()?;
    Ok(Batch {
        events: count,
        more: bytes >= 4 * 1_048_576 && c.offset < meta.len(),
    })
}

pub fn parse(v: &Value, provider: &str, c: &mut Cursor) -> Option<Event> {
    let ts = DateTime::parse_from_rfc3339(v["timestamp"].as_str()?)
        .ok()?
        .timestamp();
    if ts < 0 || ts > chrono::Utc::now().timestamp() + 300 {
        return None;
    }
    let kind = v["type"].as_str().unwrap_or("");
    let p = &v["payload"];
    if provider == "Codex" {
        if kind == "session_meta" {
            c.session = label(
                p["id"]
                    .as_str()
                    .or(p["session_id"].as_str())
                    .unwrap_or(&c.session),
            );
            c.name = project(&p["cwd"]);
        }
        if kind == "turn_context" {
            c.model = label(p["model"].as_str().unwrap_or("unknown"));
        }
        if kind != "event_msg" {
            return None;
        }
        match p["type"].as_str().unwrap_or("") {
            "task_started" => {
                c.started = ts;
                c.status = "running".into();
                c.updated = ts;
            }
            "task_complete" => {
                c.status = "completed".into();
                c.updated = ts;
            }
            "turn_aborted" | "error" => {
                c.status = "failed".into();
                c.updated = ts;
            }
            "token_count" => {
                let usage = &p["info"]["total_token_usage"];
                if !usage.is_object() {
                    return None;
                }
                let total = Tokens::codex(usage);
                let delta = total.delta(c.total);
                c.total = total;
                if delta.total() == 0 {
                    return None;
                }
                c.updated = ts;
                return Some(event(
                    c,
                    provider,
                    ts,
                    format!(
                        "{}:{ts}:{}:{}:{}:{}",
                        c.session, total.input, total.output, total.cache_read, total.cache_write
                    ),
                    delta,
                ));
            }
            _ => (),
        }
        return None;
    }
    if provider == "Claude" {
        if let Some(id) = v["sessionId"].as_str() {
            c.session = label(id);
        }
        if v["cwd"].is_string() {
            c.name = project(&v["cwd"]);
        }
        if kind == "user" {
            c.started = ts;
            c.updated = ts;
            c.status = "running".into();
        }
        if kind != "assistant" {
            return None;
        }
        let m = &v["message"];
        if !m["usage"].is_object() {
            return None;
        }
        c.model = label(m["model"].as_str().unwrap_or("unknown"));
        c.updated = ts;
        if c.started == 0 {
            c.started = ts;
        }
        c.status = if v["isApiErrorMessage"].as_bool() == Some(true) {
            "failed"
        } else if m["stop_reason"].as_str() == Some("end_turn") {
            "completed"
        } else {
            "running"
        }
        .into();
        let id = format!("{}:{}", c.session, m["id"].as_str().or(v["uuid"].as_str())?);
        return Some(event(c, provider, ts, id, Tokens::claude(&m["usage"])));
    }
    // Local agents submit metadata only, using the documented JSONL protocol.
    if provider == "Local" {
        c.session = label(v["session_id"].as_str()?);
        c.name = label(v["agent"].as_str().unwrap_or("Local agent"));
        c.model = label(v["model"].as_str().unwrap_or("local"));
        if c.started == 0 || v["status"].as_str() == Some("running") && c.status == "completed" {
            c.started = ts;
        }
        c.updated = ts;
        c.status = match v["status"].as_str().unwrap_or("waiting") {
            "running" => "running",
            "completed" => "completed",
            "failed" => "failed",
            _ => "waiting",
        }
        .into();
        if !v["usage"].is_object() {
            return None;
        }
        let mut e = event(
            c,
            provider,
            ts,
            format!("{}:{}", c.session, v["id"].as_str()?),
            Tokens::claude(&v["usage"]),
        );
        e.cost = v["cost_usd"]
            .as_f64()
            .filter(|x| x.is_finite() && *x >= 0. && *x <= 1_000_000.)
            .or(e.cost);
        return Some(e);
    }
    None
}
fn project(v: &Value) -> String {
    label(
        Path::new(v.as_str().unwrap_or(""))
            .file_name()
            .and_then(|x| x.to_str())
            .unwrap_or("Agent"),
    )
}
fn event(c: &Cursor, provider: &str, ts: i64, id: String, tokens: Tokens) -> Event {
    Event {
        id,
        timestamp: ts,
        provider: provider.into(),
        model: c.model.clone(),
        session: c.session.clone(),
        agent: c.session.clone(),
        tokens,
        cost: price(&c.model, tokens),
    }
}
