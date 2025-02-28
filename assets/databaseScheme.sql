CREATE TABLE recordings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
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
