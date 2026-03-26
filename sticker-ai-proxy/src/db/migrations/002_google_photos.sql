-- Migration 002: Google Photos integration

ALTER TABLE devices ADD COLUMN google_id TEXT;
ALTER TABLE devices ADD COLUMN google_email TEXT;
ALTER TABLE devices ADD COLUMN google_name TEXT;
ALTER TABLE devices ADD COLUMN google_photo TEXT;

CREATE TABLE IF NOT EXISTS sticker_metadata (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  sticker_index INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'static',
  emojis TEXT,
  tags TEXT,
  user_text TEXT,
  source_album TEXT,
  r2_key TEXT NOT NULL,
  thumb_r2_key TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS import_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES devices(device_id),
  album_id TEXT,
  album_name TEXT,
  total_items INTEGER NOT NULL,
  processed_items INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  owner_id TEXT NOT NULL REFERENCES devices(device_id),
  shared_with_id TEXT,
  share_code TEXT UNIQUE,
  permission TEXT DEFAULT 'view',
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sticker_metadata_pack ON sticker_metadata(pack_id);
CREATE INDEX IF NOT EXISTS idx_sticker_metadata_emojis ON sticker_metadata(emojis);
CREATE INDEX IF NOT EXISTS idx_import_jobs_user ON import_jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_shares_pack ON shares(pack_id);
CREATE INDEX IF NOT EXISTS idx_shares_shared_with ON shares(shared_with_id);
CREATE INDEX IF NOT EXISTS idx_shares_code ON shares(share_code);
