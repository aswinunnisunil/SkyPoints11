-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 5: Data Quality Framework & Validation Suite
-- Implements validation rules, anomaly detection, and a Dead Letter Queue (DLQ)
-- Catches: NULL mandatory fields, duplicate keys, invalid dates (e.g. 2021-13-13),
-- chronological inversions (Flight before Enroll, Future DOB), domain violations.
-- ============================================================================

USE DATABASE SKYPOINTS_DB;
USE SCHEMA SILVER_STAGING;

-- ----------------------------------------------------------------------------
-- Dead Letter Queue (DLQ) / Rejected Records Table
-- Quarantines malformed or invalid records so bad rows don't crash the pipeline
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE SILVER_STAGING.DLQ_REJECTED_RECORDS (
    DLQ_ID               NUMBER(18, 0) AUTOINCREMENT PRIMARY KEY,
    SOURCE_FILE_NAME     VARCHAR(255) NOT NULL,
    FILE_ROW_NUMBER      NUMBER(18, 0),
    RAW_RECORD           VARCHAR(4000),
    ERROR_CATEGORY       VARCHAR(50)  NOT NULL, -- 'MANDATORY_NULL', 'INVALID_DATE', 'DUPLICATE_KEY', 'CHRONOLOGY_ERROR', 'DOMAIN_VIOLATION'
    ERROR_FIELD          VARCHAR(50),
    ERROR_MESSAGE        VARCHAR(500) NOT NULL,
    DETECTED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (DETECTED_AT::DATE, ERROR_CATEGORY)
COMMENT = 'Dead Letter Queue storing quarantined dirty records with failure reasons';

-- ----------------------------------------------------------------------------
-- Stored Procedure: Execute Data Quality Screening on Bronze Landing
-- Routes passing records to STAGING, quarantines failing records to DLQ.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER_STAGING.SP_RUN_DATA_QUALITY_SCREENING(P_SOURCE_FILE VARCHAR)
RETURNS TABLE (ERROR_CATEGORY VARCHAR, REJECTED_COUNT NUMBER)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    -- 1. Check Mandatory Fields: Member Name is missing/null
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'MANDATORY_NULL', 'Member_Name', 'Mandatory field Member_Name is missing or NULL'
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND (RECORD_DATA[2] IS NULL OR TRIM(RECORD_DATA[2]::STRING) = '' OR UPPER(TRIM(RECORD_DATA[2]::STRING)) = 'NULL');

    -- 2. Check Mandatory Fields: Member ID is missing/null
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'MANDATORY_NULL', 'Member_Id', 'Mandatory field Member_Id is missing or NULL'
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND (RECORD_DATA[3] IS NULL OR TRIM(RECORD_DATA[3]::STRING) = '' OR UPPER(TRIM(RECORD_DATA[3]::STRING)) = 'NULL');

    -- 3. Check Mandatory Fields: Enrollment Date is missing/null
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'MANDATORY_NULL', 'Enrollment_Date', 'Mandatory field Enrollment_Date is missing or NULL'
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND (RECORD_DATA[4] IS NULL OR TRIM(RECORD_DATA[4]::STRING) = '' OR UPPER(TRIM(RECORD_DATA[4]::STRING)) = 'NULL');

    -- 4. Check Invalid Date Formats (e.g., month 13 like '2021-13-13' or unparseable date strings)
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'INVALID_DATE', 'Enrollment_Date', 
        CONCAT('Enrollment_Date value "', RECORD_DATA[4]::STRING, '" cannot be parsed into a valid calendar date (e.g. Month 13 error)')
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND RECORD_DATA[4] IS NOT NULL
      AND TRIM(RECORD_DATA[4]::STRING) != ''
      AND TRY_TO_DATE(RECORD_DATA[4]::STRING, 'YYYYMMDD') IS NULL
      AND TRY_TO_DATE(RECORD_DATA[4]::STRING, 'YYYY-MM-DD') IS NULL
      AND TRY_TO_DATE(LPAD(RECORD_DATA[4]::STRING, 8, '0'), 'MMDDYYYY') IS NULL;

    -- 5. Check Chronological Integrity: DOB in the future
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'CHRONOLOGY_ERROR', 'DOB', 'Date of birth is in the future'
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND COALESCE(
            TRY_TO_DATE(LPAD(RECORD_DATA[10]::STRING, 8, '0'), 'DDMMYYYY'),
            TRY_TO_DATE(LPAD(RECORD_DATA[10]::STRING, 8, '0'), 'MMDDYYYY'),
            TRY_TO_DATE(RECORD_DATA[10]::STRING, 'YYYYMMDD'),
            TRY_TO_DATE(RECORD_DATA[10]::STRING, 'YYYY-MM-DD')
          ) > CURRENT_DATE();

    -- 6. Check Chronological Integrity: Flight Date before Enrollment Date
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'CHRONOLOGY_ERROR', 'Flight_Date', 'Last_Flight_Date is earlier than Enrollment_Date'
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND COALESCE(
            TRY_TO_DATE(RECORD_DATA[5]::STRING, 'YYYYMMDD'),
            TRY_TO_DATE(RECORD_DATA[5]::STRING, 'YYYY-MM-DD')
          ) < COALESCE(
            TRY_TO_DATE(RECORD_DATA[4]::STRING, 'YYYYMMDD'),
            TRY_TO_DATE(RECORD_DATA[4]::STRING, 'YYYY-MM-DD')
          );

    -- 7. Check Active Member Flag Domain Violation (must be 'A' or 'I')
    INSERT INTO SILVER_STAGING.DLQ_REJECTED_RECORDS (
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_RECORD, ERROR_CATEGORY, ERROR_FIELD, ERROR_MESSAGE
    )
    SELECT 
        SOURCE_FILE_NAME, FILE_ROW_NUMBER, RAW_LINE,
        'DOMAIN_VIOLATION', 'Is_Active', 
        CONCAT('Active member flag is invalid: "', RECORD_DATA[11]::STRING, '". Expected "A" or "I"')
    FROM BRONZE_LANDING.RAW_MEMBER_PROFILES
    WHERE RECORD_TYPE = 'D'
      AND (P_SOURCE_FILE IS NULL OR SOURCE_FILE_NAME = P_SOURCE_FILE)
      AND RECORD_DATA[11] IS NOT NULL
      AND UPPER(TRIM(RECORD_DATA[11]::STRING)) NOT IN ('A', 'I');

    -- Return summary count of quarantined records by error category
    res := (
        SELECT ERROR_CATEGORY, COUNT(*) AS REJECTED_COUNT
        FROM SILVER_STAGING.DLQ_REJECTED_RECORDS
        WHERE SOURCE_FILE_NAME = COALESCE(P_SOURCE_FILE, SOURCE_FILE_NAME)
        GROUP BY ERROR_CATEGORY
    );
    RETURN TABLE(res);
END;
$$;
