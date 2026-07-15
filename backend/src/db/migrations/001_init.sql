CREATE TABLE channels (
  code       TEXT PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE messages (
  seq              INTEGER PRIMARY KEY AUTOINCREMENT,
  id               TEXT NOT NULL UNIQUE,
  channel_code     TEXT NOT NULL REFERENCES channels(code) ON DELETE CASCADE,
  filename         TEXT NOT NULL,
  size_bytes       INTEGER NOT NULL,
  duration_seconds REAL,
  sender           TEXT NOT NULL DEFAULT 'Anonyme',
  created_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX idx_messages_channel_seq ON messages(channel_code, seq);
