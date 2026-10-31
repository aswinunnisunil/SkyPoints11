-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 1 & 2: Snowflake Staging DDL & Population with Derived Columns
-- Derived columns:
--   1. Age (computed from DOB relative to current date)
--   2. Stale_Member flag ('Y'/'N' where days since Flight_Date > 90)
-- ============================================================================

USE DATABASE SKYPOINTS_DB;
USE SCHEMA SILVER_STAGING;

-- ----------------------------------------------------------------------------
-- Staging Table Definition
-- Matches data dictionary from design documents with strongly typed columns
-- and added operational metadata + derived analytical attributes.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE SILVER_STAGING.STAGING_MEMBERS (
    -- Source Business Fields
    NAME                 VARCHAR(255) NOT NULL,
    MEM_ID               VARCHAR(18)  NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10),
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),            -- Active Member flag ('A', 'I')

    -- Deliverable 2: Derived Columns
    AGE                  NUMBER(3, 0),       -- Age in full years computed from DOB
    STALE_MEMBER         CHAR(1) NOT NULL,   -- 'Y' if days since Flight_Dt > 90 or never flown, else 'N'

    -- Data Lineage & Pipeline Metadata
    _INGESTION_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    _SOURCE_ROW_ID       NUMBER(18, 0)
)
CLUSTER BY (COUNTRY, MEM_ID)
COMMENT = 'Cleansed member profiles staging table with derived Age and Stale_Member flags';

-- ----------------------------------------------------------------------------
-- Transformation & Population Query: Load Landing -> Staging
-- Parses date representations (YYYYMMDD, MMDDYYYY, YYYY-MM-DD),
-- computes Age and Stale_Member flag accurately.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER_STAGING.SP_LOAD_STAGING_MEMBERS(P_SOURCE_FILE VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO SILVER_STAGING.STAGING_MEMBERS (
        NAME,
        MEM_ID,
        ENROLL_DT,
        FLIGHT_DT,
        TIER,
        AGENT_NAME,
        STATE,
        COUNTRY,
        POST_CODE,
        DOB,
        FLAG,
        AGE,
        STALE_MEMBER,
        _INGESTION_TIMESTAMP,
        _SOURCE_FILE,
        _SOURCE_ROW_ID
    )
    WITH parsed_raw AS (
        SELECT 
            -- Pipe-delimited record position layout (skipping leading blank/delimiter):
            -- |D|Member_Name|Member_Id|Enrollment_Date|Last_Flight_Date|Tier_Code|Agent_Name|State|Country|DOB|Is_Active
            RECORD_DATA[2]::STRING  AS col_name,
            RECORD_DATA[3]::STRING  AS col_mem_id,
            RECORD_DATA[4]::STRING  AS raw_enroll_dt,
            RECORD_DATA[5]::STRING  AS raw_flight_dt,
            RECORD_DATA[6]::STRING  AS col_tier,
            RECORD_DATA[7]::STRING  AS col_agent,
            RECORD_DATA[8]::STRING  AS col_state,
            RECORD_DATA[9]::STRING  AS col_country,
            -- Check if 10th is Post Code or DOB based on pipe array length:
            IFF(ARRAY_SIZE(RECORD_DATA) > 12, RECORD_DATA[10]::STRING, NULL) AS raw_post_code,
            IFF(ARRAY_SIZE(RECORD_DATA) > 12, RECORD_DATA[11]::STRING, RECORD_DATA[10]::STRING) AS raw_dob,
            IFF(ARRAY_SIZE(RECORD_DATA) > 12, RECORD_DATA[12]::STRING, RECORD_DATA[11]::STRING) AS col_flag,
            SOURCE_FILE_NAME,
            FILE_ROW_NUMBER
        FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
        WHERE RECORD_TYPE = 'D'
          AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
    ),
    normalized_dates AS (
        SELECT 
            TRIM(col_name) AS NAME,
            TRIM(col_mem_id) AS MEM_ID,

            -- Robust date parsing for ENROLL_DT (supports YYYYMMDD, YYYY-MM-DD, MMDDYYYY)
            COALESCE(
                TRY_TO_DATE(raw_enroll_dt, 'YYYYMMDD'),
                TRY_TO_DATE(raw_enroll_dt, 'YYYY-MM-DD'),
                TRY_TO_DATE(LPAD(raw_enroll_dt, 8, '0'), 'MMDDYYYY')
            ) AS ENROLL_DT,

            -- Robust date parsing for FLIGHT_DT
            COALESCE(
                TRY_TO_DATE(raw_flight_dt, 'YYYYMMDD'),
                TRY_TO_DATE(raw_flight_dt, 'YYYY-MM-DD'),
                TRY_TO_DATE(LPAD(raw_flight_dt, 8, '0'), 'MMDDYYYY')
            ) AS FLIGHT_DT,

            UPPER(TRIM(col_tier)) AS TIER,
            TRIM(col_agent) AS AGENT_NAME,
            UPPER(TRIM(col_state)) AS STATE,
            UPPER(TRIM(col_country)) AS COUNTRY,
            TRY_TO_NUMBER(raw_post_code) AS POST_CODE,

            -- Robust date parsing for DOB (supports DDMMYYYY, MMDDYYYY, YYYY-MM-DD, YYYYMMDD)
            COALESCE(
                TRY_TO_DATE(LPAD(raw_dob, 8, '0'), 'DDMMYYYY'),
                TRY_TO_DATE(LPAD(raw_dob, 8, '0'), 'MMDDYYYY'),
                TRY_TO_DATE(raw_dob, 'YYYYMMDD'),
                TRY_TO_DATE(raw_dob, 'YYYY-MM-DD')
            ) AS DOB,

            UPPER(TRIM(col_flag)) AS FLAG,
            SOURCE_FILE_NAME,
            FILE_ROW_NUMBER
        FROM parsed_raw
    )
    SELECT 
        NAME,
        MEM_ID,
        ENROLL_DT,
        FLIGHT_DT,
        TIER,
        AGENT_NAME,
        STATE,
        COUNTRY,
        POST_CODE,
        DOB,
        FLAG,

        -- Deliverable 2: Derived Column 1 - Age
        -- Evaluates completed chronological years from DOB to current date
        CASE 
            WHEN DOB IS NULL THEN NULL
            WHEN DOB > CURRENT_DATE() THEN NULL -- Caught by DQ validation
            ELSE DATEDIFF('year', DOB, CURRENT_DATE()) - 
                 IFF(DATEADD('year', DATEDIFF('year', DOB, CURRENT_DATE()), DOB) > CURRENT_DATE(), 1, 0)
        END AS AGE,

        -- Deliverable 2: Derived Column 2 - Stale_Member Flag
        -- 'Y' if days since Flight_Date > 90 days or if the member has never flown (FLIGHT_DT IS NULL), else 'N'
        CASE 
            WHEN FLIGHT_DT IS NULL THEN 'Y'
            WHEN DATEDIFF('day', FLIGHT_DT, CURRENT_DATE()) > 90 THEN 'Y'
            ELSE 'N'
        END AS STALE_MEMBER,

        CURRENT_TIMESTAMP(),
        SOURCE_FILE_NAME,
        FILE_ROW_NUMBER
    FROM normalized_dates
    WHERE NAME IS NOT NULL 
      AND MEM_ID IS NOT NULL 
      AND ENROLL_DT IS NOT NULL;

    RETURN 'Staging table populated successfully with derived columns.';
END;
$$;
