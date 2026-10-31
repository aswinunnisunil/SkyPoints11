-- ============================================================================
-- Local SQLite / ANSI SQL DDL for SkyPoints Loyalty Data Pipeline
-- Allows 100% offline local execution, testing, and live demonstration
-- ============================================================================

-- 1. Raw / Landing Tables
CREATE TABLE IF NOT EXISTS raw_member_profiles (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    record_type          TEXT,
    raw_line             TEXT,
    source_file_name     TEXT NOT NULL,
    file_row_number      INTEGER NOT NULL,
    ingestion_timestamp  TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS raw_redemption_feeds (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_payload          TEXT NOT NULL,
    source_file_name     TEXT NOT NULL,
    ingestion_timestamp  TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 2. Staging Table with Derived Columns
CREATE TABLE IF NOT EXISTS staging_members (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    name                 TEXT NOT NULL,
    mem_id               TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT,
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    _ingestion_timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT,
    _source_row_id       INTEGER
);

-- 3. Dead Letter Queue (DLQ)
CREATE TABLE IF NOT EXISTS dlq_rejected_records (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    source_file_name     TEXT,
    file_row_number      INTEGER,
    raw_record           TEXT,
    error_category       TEXT NOT NULL,
    error_field          TEXT,
    error_message        TEXT NOT NULL,
    detected_at          TEXT DEFAULT CURRENT_TIMESTAMP
);

-- 4. Per-Country Target Tables
CREATE TABLE IF NOT EXISTS table_india (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL DEFAULT 'IND',
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

CREATE TABLE IF NOT EXISTS table_usa (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL DEFAULT 'USA',
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

CREATE TABLE IF NOT EXISTS table_canada (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL DEFAULT 'CAN',
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

CREATE TABLE IF NOT EXISTS table_philippines (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL DEFAULT 'PHIL',
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

CREATE TABLE IF NOT EXISTS table_australia (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL DEFAULT 'AU',
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

CREATE TABLE IF NOT EXISTS table_other_countries (
    mem_id               TEXT PRIMARY KEY,
    name                 TEXT NOT NULL,
    enroll_dt            TEXT NOT NULL,
    flight_dt            TEXT,
    tier                 TEXT,
    agent_name           TEXT,
    state                TEXT,
    country              TEXT NOT NULL,
    post_code            INTEGER,
    dob                  TEXT,
    flag                 TEXT,
    age                  INTEGER,
    stale_member         TEXT NOT NULL,
    updated_at           TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);

-- 5. Flattened Queryable Redemptions Table
CREATE TABLE IF NOT EXISTS fact_member_redemptions (
    txn_id               TEXT PRIMARY KEY,
    member_id            TEXT NOT NULL,
    feed_date            TEXT NOT NULL,
    txn_date             TEXT NOT NULL,
    partner              TEXT NOT NULL,
    miles_redeemed       INTEGER NOT NULL,
    status               TEXT NOT NULL,
    ingestion_timestamp  TEXT DEFAULT CURRENT_TIMESTAMP,
    _source_file         TEXT
);
