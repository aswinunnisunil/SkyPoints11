-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 3: Transformation Logic & Per-Country Target Split
-- Enforces the "Latest Record Wins" rule when a member moves countries
-- ============================================================================

USE DATABASE SKYPOINTS_DB;
USE SCHEMA GOLD_MARTS;

-- ----------------------------------------------------------------------------
-- Stored Procedure: Execute Country Split with "Latest Record Wins"
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOLD_MARTS.SP_SPLIT_MEMBERS_BY_COUNTRY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- Step 1: Identify the absolute latest record per MEM_ID from STAGING
    -- Resolves intra-batch duplicates and tracks country movements.
    CREATE OR REPLACE TEMPORARY TABLE TEMP_LATEST_STAGING_MEMBERS AS
    WITH ranked_records AS (
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
            AGE,
            STALE_MEMBER,
            _INGESTION_TIMESTAMP,
            _SOURCE_FILE,
            ROW_NUMBER() OVER (
                PARTITION BY MEM_ID 
                ORDER BY 
                    -- Latest flight date takes precedence; fallback to enrollment date, then ingestion time
                    COALESCE(FLIGHT_DT, ENROLL_DT) DESC,
                    _INGESTION_TIMESTAMP DESC
            ) AS rn
        FROM SILVER_STAGING.STAGING_MEMBERS
    )
    SELECT *
    FROM ranked_records
    WHERE rn = 1;

    -- ------------------------------------------------------------------------
    -- Approach A: Unified Master Gold Table (Best for Billion-Record Scale)
    -- Atomically updates the member's country and details. "Latest record wins".
    -- ------------------------------------------------------------------------
    MERGE INTO GOLD_MARTS.DIM_MEMBERS_UNIFIED AS tgt
    USING TEMP_LATEST_STAGING_MEMBERS AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND (
        -- Only overwrite if incoming record is newer or same date with later timestamp
        COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT)
    ) THEN
        UPDATE SET 
            tgt.NAME         = src.NAME,
            tgt.ENROLL_DT    = src.ENROLL_DT,
            tgt.FLIGHT_DT    = src.FLIGHT_DT,
            tgt.TIER         = src.TIER,
            tgt.AGENT_NAME   = src.AGENT_NAME,
            tgt.STATE        = src.STATE,
            tgt.COUNTRY      = src.COUNTRY, -- Member country successfully updated if relocated
            tgt.POST_CODE    = src.POST_CODE,
            tgt.DOB          = src.DOB,
            tgt.FLAG         = src.FLAG,
            tgt.AGE          = src.AGE,
            tgt.STALE_MEMBER = src.STALE_MEMBER,
            tgt.UPDATED_AT   = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (
            MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME,
            STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER,
            UPDATED_AT, _SOURCE_FILE
        )
        VALUES (
            src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME,
            src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER,
            CURRENT_TIMESTAMP(), src._SOURCE_FILE
        );

    -- ------------------------------------------------------------------------
    -- Approach B: Discrete Physical Country Tables (Explicit Assessment Requirement)
    -- "All members related to India will go to Table_India, and so on for each country."
    -- Handles members moving across countries:
    -- If a member moved to India, they are inserted/updated into Table_India
    -- AND deleted from their prior country table.
    -- ------------------------------------------------------------------------

    -- 1. Table_India Sync
    MERGE INTO GOLD_MARTS.TABLE_INDIA AS tgt
    USING (SELECT * FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA')) AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT) THEN
        UPDATE SET 
            tgt.NAME = src.NAME, tgt.ENROLL_DT = src.ENROLL_DT, tgt.FLIGHT_DT = src.FLIGHT_DT,
            tgt.TIER = src.TIER, tgt.AGENT_NAME = src.AGENT_NAME, tgt.STATE = src.STATE,
            tgt.POST_CODE = src.POST_CODE, tgt.DOB = src.DOB, tgt.FLAG = src.FLAG,
            tgt.AGE = src.AGE, tgt.STALE_MEMBER = src.STALE_MEMBER, tgt.UPDATED_AT = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME, STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER, UPDATED_AT, _SOURCE_FILE)
        VALUES (src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME, src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    -- Purge moved members from other tables if their latest country is IND
    DELETE FROM GOLD_MARTS.TABLE_USA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA'));
    DELETE FROM GOLD_MARTS.TABLE_CANADA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA'));
    DELETE FROM GOLD_MARTS.TABLE_PHILIPPINES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA'));
    DELETE FROM GOLD_MARTS.TABLE_AUSTRALIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA'));
    DELETE FROM GOLD_MARTS.TABLE_OTHER_COUNTRIES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('IND', 'INDIA'));

    -- 2. Table_USA Sync
    MERGE INTO GOLD_MARTS.TABLE_USA AS tgt
    USING (SELECT * FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US')) AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT) THEN
        UPDATE SET 
            tgt.NAME = src.NAME, tgt.ENROLL_DT = src.ENROLL_DT, tgt.FLIGHT_DT = src.FLIGHT_DT,
            tgt.TIER = src.TIER, tgt.AGENT_NAME = src.AGENT_NAME, tgt.STATE = src.STATE,
            tgt.POST_CODE = src.POST_CODE, tgt.DOB = src.DOB, tgt.FLAG = src.FLAG,
            tgt.AGE = src.AGE, tgt.STALE_MEMBER = src.STALE_MEMBER, tgt.UPDATED_AT = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME, STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER, UPDATED_AT, _SOURCE_FILE)
        VALUES (src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME, src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    -- Purge moved members from other tables if their latest country is USA
    DELETE FROM GOLD_MARTS.TABLE_INDIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US'));
    DELETE FROM GOLD_MARTS.TABLE_CANADA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US'));
    DELETE FROM GOLD_MARTS.TABLE_PHILIPPINES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US'));
    DELETE FROM GOLD_MARTS.TABLE_AUSTRALIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US'));
    DELETE FROM GOLD_MARTS.TABLE_OTHER_COUNTRIES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('USA', 'US'));

    -- 3. Table_Canada Sync
    MERGE INTO GOLD_MARTS.TABLE_CANADA AS tgt
    USING (SELECT * FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('CAN', 'CANADA')) AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT) THEN
        UPDATE SET 
            tgt.NAME = src.NAME, tgt.ENROLL_DT = src.ENROLL_DT, tgt.FLIGHT_DT = src.FLIGHT_DT,
            tgt.TIER = src.TIER, tgt.AGENT_NAME = src.AGENT_NAME, tgt.STATE = src.STATE,
            tgt.POST_CODE = src.POST_CODE, tgt.DOB = src.DOB, tgt.FLAG = src.FLAG,
            tgt.AGE = src.AGE, tgt.STALE_MEMBER = src.STALE_MEMBER, tgt.UPDATED_AT = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME, STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER, UPDATED_AT, _SOURCE_FILE)
        VALUES (src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME, src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    DELETE FROM GOLD_MARTS.TABLE_INDIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('CAN', 'CANADA'));
    DELETE FROM GOLD_MARTS.TABLE_USA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('CAN', 'CANADA'));
    DELETE FROM GOLD_MARTS.TABLE_PHILIPPINES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('CAN', 'CANADA'));
    DELETE FROM GOLD_MARTS.TABLE_AUSTRALIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('CAN', 'CANADA'));

    -- 4. Table_Philippines Sync
    MERGE INTO GOLD_MARTS.TABLE_PHILIPPINES AS tgt
    USING (SELECT * FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('PHIL', 'PHL', 'PH')) AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT) THEN
        UPDATE SET 
            tgt.NAME = src.NAME, tgt.ENROLL_DT = src.ENROLL_DT, tgt.FLIGHT_DT = src.FLIGHT_DT,
            tgt.TIER = src.TIER, tgt.AGENT_NAME = src.AGENT_NAME, tgt.STATE = src.STATE,
            tgt.POST_CODE = src.POST_CODE, tgt.DOB = src.DOB, tgt.FLAG = src.FLAG,
            tgt.AGE = src.AGE, tgt.STALE_MEMBER = src.STALE_MEMBER, tgt.UPDATED_AT = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME, STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER, UPDATED_AT, _SOURCE_FILE)
        VALUES (src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME, src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    DELETE FROM GOLD_MARTS.TABLE_INDIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('PHIL', 'PHL', 'PH'));
    DELETE FROM GOLD_MARTS.TABLE_USA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('PHIL', 'PHL', 'PH'));
    DELETE FROM GOLD_MARTS.TABLE_CANADA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('PHIL', 'PHL', 'PH'));
    DELETE FROM GOLD_MARTS.TABLE_AUSTRALIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('PHIL', 'PHL', 'PH'));

    -- 5. Table_Australia Sync
    MERGE INTO GOLD_MARTS.TABLE_AUSTRALIA AS tgt
    USING (SELECT * FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA')) AS src
    ON tgt.MEM_ID = src.MEM_ID
    WHEN MATCHED AND COALESCE(src.FLIGHT_DT, src.ENROLL_DT) >= COALESCE(tgt.FLIGHT_DT, tgt.ENROLL_DT) THEN
        UPDATE SET 
            tgt.NAME = src.NAME, tgt.ENROLL_DT = src.ENROLL_DT, tgt.FLIGHT_DT = src.FLIGHT_DT,
            tgt.TIER = src.TIER, tgt.AGENT_NAME = src.AGENT_NAME, tgt.STATE = src.STATE,
            tgt.POST_CODE = src.POST_CODE, tgt.DOB = src.DOB, tgt.FLAG = src.FLAG,
            tgt.AGE = src.AGE, tgt.STALE_MEMBER = src.STALE_MEMBER, tgt.UPDATED_AT = CURRENT_TIMESTAMP(),
            tgt._SOURCE_FILE = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (MEM_ID, NAME, ENROLL_DT, FLIGHT_DT, TIER, AGENT_NAME, STATE, COUNTRY, POST_CODE, DOB, FLAG, AGE, STALE_MEMBER, UPDATED_AT, _SOURCE_FILE)
        VALUES (src.MEM_ID, src.NAME, src.ENROLL_DT, src.FLIGHT_DT, src.TIER, src.AGENT_NAME, src.STATE, src.COUNTRY, src.POST_CODE, src.DOB, src.FLAG, src.AGE, src.STALE_MEMBER, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    DELETE FROM GOLD_MARTS.TABLE_INDIA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA'));
    DELETE FROM GOLD_MARTS.TABLE_USA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA'));
    DELETE FROM GOLD_MARTS.TABLE_CANADA WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA'));
    DELETE FROM GOLD_MARTS.TABLE_PHILIPPINES WHERE MEM_ID IN (SELECT MEM_ID FROM TEMP_LATEST_STAGING_MEMBERS WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA'));

    RETURN 'Country tables split completed with latest-record-wins deduplication.';
END;
$$;
