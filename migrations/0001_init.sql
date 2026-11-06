CREATE TABLE players (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_key TEXT NOT NULL UNIQUE,
  is_admin INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

-- One row per Blazers game. questions and final are JSON.
CREATE TABLE games (
  id TEXT PRIMARY KEY,          -- ESPN event id
  tip TEXT NOT NULL,            -- ISO time, UTC
  home INTEGER NOT NULL,
  opp TEXT NOT NULL,            -- ESPN abbreviation (LAL, GS, NY...)
  opp_name TEXT NOT NULL,
  questions TEXT,
  final TEXT,
  updated_at TEXT
);

CREATE TABLE picks (
  player_id TEXT NOT NULL REFERENCES players(id),
  game_id TEXT NOT NULL REFERENCES games(id),
  winner TEXT,
  q TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  PRIMARY KEY (player_id, game_id)
);
