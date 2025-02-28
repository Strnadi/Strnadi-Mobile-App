CREATE TABLE recordings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    estimated_birds_count INTEGER NOT NULL,
    device TEXT NOT NULL,
    by_app INTEGER NOT NULL, -- 1 = true, 0 = false
    note TEXT,
    filepath TEXT NOT NULL, -- Path to the full recording file
    latitude REAL,
    longitude REAL,
    upload_status INTEGER DEFAULT 0 -- 0 = pending, 1 = uploaded
);

CREATE TABLE recording_parts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recording_id INTEGER NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    latitude REAL,
    longitude REAL,
    FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
);

