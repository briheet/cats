use crate::domain::ProviderKind;
use crate::{Result, collectors::Cursor, telemetry::Event};
use rusqlite::{Connection, OptionalExtension, params};
use std::path::Path;

#[derive(Debug)]
pub struct Store {
    pub(crate) db: Connection,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let db = Connection::open(path)?;
        db.busy_timeout(std::time::Duration::from_secs(3))?;
        db.execute_batch(include_str!("../migrations/001.sql"))?;
        Ok(Self { db })
    }

    pub fn connection(&self) -> &Connection {
        &self.db
    }

    pub fn cursor(&self, path: &str) -> Result<Cursor> {
        let json: Option<String> = self
            .db
            .query_row("SELECT state FROM cursors WHERE path=?", [path], |row| {
                row.get(0)
            })
            .optional()?;
        Ok(match json {
            Some(json) => serde_json::from_str(&json)?,
            None => Cursor::default(),
        })
    }

    /// Commit cursor and lifecycle metadata in the same transaction as usage.
    pub fn save_cursor(
        db: &Connection,
        path: &str,
        provider: ProviderKind,
        cursor: &Cursor,
    ) -> Result<()> {
        db.execute(
            "INSERT INTO cursors (path, state) VALUES (?1, ?2)
             ON CONFLICT(path) DO UPDATE SET state=excluded.state",
            params![path, serde_json::to_string(cursor)?],
        )?;
        if cursor.updated > 0 {
            db.execute(
                "INSERT INTO agents (id, provider, session, name, status, started, updated)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(id) DO UPDATE SET
                   name=excluded.name, status=excluded.status,
                   started=excluded.started, updated=excluded.updated
                 WHERE excluded.updated>=agents.updated",
                params![
                    format!("{provider}:{}", cursor.session),
                    provider,
                    cursor.session,
                    if cursor.name.is_empty() {
                        "Agent"
                    } else {
                        &cursor.name
                    },
                    cursor.status,
                    cursor.started,
                    cursor.updated,
                ],
            )?;
        }
        Ok(())
    }

    /// Upsert growing streaming usage without duplicating an assistant message.
    pub fn insert(db: &Connection, event: &Event) -> Result<usize> {
        Ok(db.execute(
            "INSERT INTO events
               (id, timestamp, provider, model, session, agent,
                input, output, cache_read, cache_write, cache_write_1h, cost)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
             ON CONFLICT(provider,id) DO UPDATE SET
               input=excluded.input, output=excluded.output,
               cache_read=excluded.cache_read, cache_write=excluded.cache_write,
               cache_write_1h=excluded.cache_write_1h, cost=excluded.cost
             WHERE excluded.input+excluded.output+excluded.cache_read
                   +excluded.cache_write+excluded.cache_write_1h
                 > events.input+events.output+events.cache_read
                   +events.cache_write+events.cache_write_1h",
            params![
                event.id,
                event.timestamp,
                event.provider,
                event.model,
                event.session,
                event.agent,
                event.tokens.input as i64,
                event.tokens.output as i64,
                event.tokens.cache_read as i64,
                event.tokens.cache_write as i64,
                event.tokens.cache_write_1h as i64,
                event.cost,
            ],
        )?)
    }
}
