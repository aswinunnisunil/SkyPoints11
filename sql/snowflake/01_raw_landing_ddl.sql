-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 1: Snowflake DDL - Raw / Landing Layer (Bronze)
-- Designed for Billion-Record Daily Ingestion Scale
-- ============================================================================

-- Create Database and Schemas
CREATE DATABASE IF NOT EXISTS SKYPOINTS_DB;
USE DATABASE SKYPOINTS_DB;

CREATE SCHEMA IF NOT EXISTS BRONZE_LANDING COMMENT = 'Raw landing zone for ingested files with zero transformation';
CREATE SCHEMA IF NOT EXISTS SILVER_STAGING COMMENT = 'Validated, cleansed staging layer with derived attributes';
CREATE SCHEMA IF NOT EXISTS GOLD_MARTS     COMMENT = 'Per-country business target tables and analytical data marts';

-- ----------------------------------------------------------------------------
-- File Formats
-- ----------------------------------------------------------------------------
-- File format for pipe-delimited member profile files
CREATE OR REPLACE FILE FORMAT BRONZE_LANDING.FF_PIPE_DELIMITED
    TYPE = 'CSV'
    FIELD_DELIMITER = '|'
    SKIP_HEADER = 0
    FIELD_OPTIONALLY_ENCLOSED_BY = 'NONE'
    TRIM_SPACE = TRUE
    NULL_IF = ('NULL', 'null', '', ' ')
    EMPTY_FIELD_AS_NULL = TRUE
    ENCODING = 'UTF8';

-- File format for semi-structured partner redemption JSON feed
CREATE OR REPLACE FILE FORMAT BRONZE_LANDING.FF_JSON_FEED
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE
    ENABLE_OCTAL = FALSE
    ALLOW_DUPLICATE = FALSE
    STRIP_NULL_VALUES = FALSE
    IGNORE_UTF8_ERRORS = FALSE;

-- ----------------------------------------------------------------------------
-- Storage Stages (External S3/GCS or Internal Snowflake Stage)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE STAGE BRONZE_LANDING.STAGE_MEMBER_PROFILES
    FILE_FORMAT = BRONZE_LANDING.FF_PIPE_DELIMITED
    COMMENT = 'Stage for daily incoming member profile flat files';

CREATE OR REPLACE STAGE BRONZE_LANDING.STAGE_REDEMPTIONS
    FILE_FORMAT = BRONZE_LANDING.FF_JSON_FEED
    COMMENT = 'Stage for daily partner airline JSON redemption feeds';

-- ----------------------------------------------------------------------------
-- Raw / Landing Tables
-- ----------------------------------------------------------------------------
-- 1. Raw Flat File Landing Table:
-- Stores raw line records as strings or variant with metadata to enable idempotency and lineage
CREATE OR REPLACE TABLE BRONZE_LANDING.RAW_MEMBER_PROFILES (
    RECORD_TYPE          VARCHAR(5),        -- 'H' for Header, 'D' for Detail
    RAW_LINE             VARCHAR(4000),     -- Full raw line payload
    RECORD_DATA          VARIANT,           -- Parsed line array for fast column indexing
    SOURCE_FILE_NAME     VARCHAR(255) NOT NULL,
    FILE_ROW_NUMBER      NUMBER(18, 0) NOT NULL,
    INGESTION_TIMESTAMP  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (INGESTION_TIMESTAMP::DATE, SOURCE_FILE_NAME)
COMMENT = 'Raw landing table storing flat file rows verbatim for auditability';

-- 2. Raw JSON Redemption Landing Table:
-- Stores partner airline semi-structured JSON payloads in native Snowflake VARIANT
CREATE OR REPLACE TABLE BRONZE_LANDING.RAW_REDEMPTION_FEEDS (
    RAW_PAYLOAD          VARIANT NOT NULL,  -- Entire JSON object per member feed
    SOURCE_FILE_NAME     VARCHAR(255) NOT NULL,
    INGESTION_TIMESTAMP  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (INGESTION_TIMESTAMP::DATE)
COMMENT = 'Raw landing table storing semi-structured JSON redemption payloads';

-- ----------------------------------------------------------------------------
-- Continuous Automated Ingestion via Snowpipe (For Billion-Record Scalability)
-- ----------------------------------------------------------------------------
-- Snowpipe for Member Profiles flat files
CREATE OR REPLACE PIPE BRONZE_LANDING.PIPE_MEMBER_PROFILES_INGEST
    AUTO_INGEST = TRUE
    AS
    COPY INTO BRONZE_LANDING.RAW_MEMBER_PROFILES (
        RECORD_TYPE,
        RAW_LINE,
        RECORD_DATA,
        SOURCE_FILE_NAME,
        FILE_ROW_NUMBER,
        INGESTION_TIMESTAMP
    )
    FROM (
        SELECT 
            SPLIT_PART($1, '|', 2),
            $1,
            SPLIT($1, '|'),
            METADATA$FILENAME,
            METADATA$FILE_ROW_NUMBER,
            CURRENT_TIMESTAMP()
        FROM @BRONZE_LANDING.STAGE_MEMBER_PROFILES
    );

-- Snowpipe for Redemption JSON feed
CREATE OR REPLACE PIPE BRONZE_LANDING.PIPE_REDEMPTIONS_INGEST
    AUTO_INGEST = TRUE
    AS
    COPY INTO BRONZE_LANDING.RAW_REDEMPTION_FEEDS (
        RAW_PAYLOAD,
        SOURCE_FILE_NAME,
        INGESTION_TIMESTAMP
    )
    FROM (
        SELECT 
            $1,
            METADATA$FILENAME,
            CURRENT_TIMESTAMP()
        FROM @BRONZE_LANDING.STAGE_REDEMPTIONS
    );
