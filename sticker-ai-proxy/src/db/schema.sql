-- StickerOfficer D1 Schema
-- 10 tables: devices, packs, stickers, likes, downloads,
--            challenges, challenge_submissions, challenge_votes, reports, blocks

CREATE TABLE devices (
  device_id TEXT PRIMARY KEY,
  public_id TEXT UNIQUE NOT NULL,
  display_name TEXT,
  terms_accepted_at TEXT,
  is_blocked BOOLEAN DEFAULT FALSE,
  packs_created INTEGER DEFAULT 0,
  total_likes_received INTEGER DEFAULT 0,
  first_seen TEXT DEFAULT (datetime('now')),
  last_seen TEXT DEFAULT (datetime('now'))
);

CREATE TABLE packs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  author_device_id TEXT NOT NULL REFERENCES devices(device_id),
  category TEXT,
  sticker_count INTEGER DEFAULT 0,
  like_count INTEGER DEFAULT 0,
  download_count INTEGER DEFAULT 0,
  is_public BOOLEAN DEFAULT FALSE,
  is_removed BOOLEAN DEFAULT FALSE,
  tags TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE stickers (
  id TEXT PRIMARY KEY,
  pack_id TEXT NOT NULL REFERENCES packs(id),
  r2_key TEXT NOT NULL,
  position INTEGER DEFAULT 0
);

CREATE TABLE likes (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  pack_id TEXT NOT NULL REFERENCES packs(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, pack_id)
);

CREATE TABLE downloads (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  pack_id TEXT NOT NULL REFERENCES packs(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, pack_id)
);

CREATE TABLE challenges (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  theme TEXT NOT NULL,
  status TEXT DEFAULT 'upcoming',
  starts_at TEXT NOT NULL,
  voting_at TEXT NOT NULL,
  ends_at TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE challenge_submissions (
  id TEXT PRIMARY KEY,
  challenge_id TEXT NOT NULL REFERENCES challenges(id),
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  sticker_r2_key TEXT NOT NULL,
  vote_count INTEGER DEFAULT 0,
  is_removed BOOLEAN DEFAULT FALSE,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE challenge_votes (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  submission_id TEXT NOT NULL REFERENCES challenge_submissions(id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (device_id, submission_id)
);

CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  reporter_device_id TEXT NOT NULL REFERENCES devices(device_id),
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  details TEXT,
  status TEXT DEFAULT 'pending',
  reviewed_at TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE blocks (
  blocker_device_id TEXT NOT NULL REFERENCES devices(device_id),
  blocked_device_id TEXT NOT NULL REFERENCES devices(device_id),
  created_at TEXT DEFAULT (datetime('now')),
  PRIMARY KEY (blocker_device_id, blocked_device_id)
);
