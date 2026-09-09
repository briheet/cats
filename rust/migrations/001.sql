PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
CREATE TABLE IF NOT EXISTS events (
 id TEXT NOT NULL, timestamp INTEGER NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
 session TEXT NOT NULL, agent TEXT NOT NULL, input INTEGER NOT NULL, output INTEGER NOT NULL,
 cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL, cache_write_1h INTEGER NOT NULL,
 cost REAL, PRIMARY KEY(provider,id)
);
CREATE INDEX IF NOT EXISTS events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS events_provider ON events(provider,timestamp);
CREATE INDEX IF NOT EXISTS events_session ON events(session);
CREATE INDEX IF NOT EXISTS events_agent ON events(agent);
CREATE TABLE IF NOT EXISTS cursors (path TEXT PRIMARY KEY, state TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS agents (
 id TEXT PRIMARY KEY, provider TEXT NOT NULL, session TEXT NOT NULL, name TEXT NOT NULL,
 status TEXT NOT NULL, started INTEGER NOT NULL, updated INTEGER NOT NULL
);
PRAGMA user_version=1;
