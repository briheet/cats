use crate::{Result, collectors::Cursor, telemetry::Event};
use rusqlite::{Connection, OptionalExtension, params};
use std::path::Path;

pub struct Store {
    pub db: Connection,
}
impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let db = Connection::open(path)?;
        db.busy_timeout(std::time::Duration::from_secs(3))?;
        db.execute_batch(include_str!("../migrations/001.sql"))?;
        Ok(Self { db })
    }
    pub fn cursor(&self, path: &str) -> Result<Cursor> {
        let json: Option<String> = self
            .db
            .query_row("SELECT state FROM cursors WHERE path=?", [path], |r| {
                r.get(0)
            })
            .optional()?;
        Ok(match json {
            Some(j) => serde_json::from_str(&j)?,
            None => Cursor::default(),
        })
    }
    pub fn save_cursor(db: &Connection, path: &str, provider: &str, c: &Cursor) -> Result<()> {
        db.execute("INSERT INTO cursors VALUES (?1,?2) ON CONFLICT(path) DO UPDATE SET state=excluded.state", params![path, serde_json::to_string(c)?])?;
        if c.updated > 0 {
            db.execute("INSERT INTO agents VALUES (?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(id) DO UPDATE SET name=excluded.name, status=excluded.status, started=excluded.started, updated=excluded.updated WHERE excluded.updated>=agents.updated",
                params![format!("{provider}:{}", c.session), provider, c.session, if c.name.is_empty() { "Agent" } else { &c.name }, c.status, c.started, c.updated])?;
        }
        Ok(())
    }
    pub fn insert(db: &Connection, e: &Event) -> Result<usize> {
        // Claude can repeat an assistant message as streaming usage grows.
        Ok(db.execute("INSERT INTO events VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)
          ON CONFLICT(provider,id) DO UPDATE SET input=excluded.input, output=excluded.output,
          cache_read=excluded.cache_read, cache_write=excluded.cache_write, cache_write_1h=excluded.cache_write_1h, cost=excluded.cost
          WHERE excluded.input+excluded.output+excluded.cache_read+excluded.cache_write+excluded.cache_write_1h > events.input+events.output+events.cache_read+events.cache_write+events.cache_write_1h",
          params![e.id, e.timestamp, e.provider, e.model, e.session, e.agent, e.tokens.input as i64, e.tokens.output as i64, e.tokens.cache_read as i64, e.tokens.cache_write as i64, e.tokens.cache_write_1h as i64, e.cost])?)
    }
}
