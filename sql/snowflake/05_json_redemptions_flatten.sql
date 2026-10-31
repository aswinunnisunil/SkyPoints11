-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 4: Semi-Structured JSON Redemption Feed Parsing & Joins
-- Flattens JSON payloads with LATERAL FLATTEN into queryable relational model
-- and defines analytical 360-degree loyalty joins back to member profile data.
-- ============================================================================

USE DATABASE SKYPOINTS_DB;
USE SCHEMA GOLD_MARTS;

-- ----------------------------------------------------------------------------
-- 1. Flattened Queryable Target Table
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE GOLD_MARTS.FACT_MEMBER_REDEMPTIONS (
    TXN_ID               VARCHAR(30)  NOT NULL,
    MEMBER_ID            VARCHAR(18)  NOT NULL,
    FEED_DATE            DATE         NOT NULL,
    TXN_DATE             DATE         NOT NULL,
    PARTNER              VARCHAR(100) NOT NULL,
    MILES_REDEEMED       NUMBER(12, 0) NOT NULL,
    STATUS               VARCHAR(20)  NOT NULL, -- 'COMPLETED', 'PENDING', 'CANCELLED'
    INGESTION_TIMESTAMP  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_REDEMPTIONS PRIMARY KEY (TXN_ID)
)
CLUSTER BY (MEMBER_ID, TXN_DATE)
COMMENT = 'Flattened transaction-level mileage redemptions parsed from partner airline JSON feeds';

-- ----------------------------------------------------------------------------
-- 2. Parsing & Loading Procedure: Extract Nested Arrays via LATERAL FLATTEN
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOLD_MARTS.SP_FLATTEN_REDEMPTION_FEEDS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO GOLD_MARTS.FACT_MEMBER_REDEMPTIONS AS tgt
    USING (
        SELECT 
            r.value:txn_id::STRING                     AS TXN_ID,
            TRIM(f.RAW_PAYLOAD:member_id::STRING)       AS MEMBER_ID,
            TRY_TO_DATE(f.RAW_PAYLOAD:feed_date::STRING, 'YYYYMMDD') AS FEED_DATE,
            TRY_TO_DATE(r.value:txn_date::STRING, 'YYYYMMDD')        AS TXN_DATE,
            TRIM(r.value:partner::STRING)               AS PARTNER,
            r.value:miles_redeemed::NUMBER(12, 0)       AS MILES_REDEEMED,
            UPPER(TRIM(r.value:status::STRING))         AS STATUS,
            f.SOURCE_FILE_NAME                         AS _SOURCE_FILE
        FROM BRONZE_LANDING.RAW_REDEMPTION_FEEDS f,
             LATERAL FLATTEN(input => f.RAW_PAYLOAD:redemptions) r
        WHERE r.value:txn_id IS NOT NULL 
          AND f.RAW_PAYLOAD:member_id IS NOT NULL
    ) AS src
    ON tgt.TXN_ID = src.TXN_ID
    WHEN MATCHED THEN
        UPDATE SET 
            tgt.MEMBER_ID      = src.MEMBER_ID,
            tgt.FEED_DATE      = src.FEED_DATE,
            tgt.TXN_DATE       = src.TXN_DATE,
            tgt.PARTNER        = src.PARTNER,
            tgt.MILES_REDEEMED = src.MILES_REDEEMED,
            tgt.STATUS         = src.STATUS,
            tgt._SOURCE_FILE   = src._SOURCE_FILE
    WHEN NOT MATCHED THEN
        INSERT (TXN_ID, MEMBER_ID, FEED_DATE, TXN_DATE, PARTNER, MILES_REDEEMED, STATUS, INGESTION_TIMESTAMP, _SOURCE_FILE)
        VALUES (src.TXN_ID, src.MEMBER_ID, src.FEED_DATE, src.TXN_DATE, src.PARTNER, src.MILES_REDEEMED, src.STATUS, CURRENT_TIMESTAMP(), src._SOURCE_FILE);

    RETURN 'JSON redemptions flattened and merged successfully.';
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Analytical Joins: Joining Flattened Redemptions to Member Profiles
-- ----------------------------------------------------------------------------

-- A. Member Loyalty 360 View:
-- Joins member profile (with Country, Tier, Age, Stale status) with transaction details.
CREATE OR REPLACE VIEW GOLD_MARTS.VW_MEMBER_LOYALTY_360 AS
SELECT 
    m.MEM_ID,
    m.NAME,
    m.COUNTRY,
    m.STATE,
    m.TIER,
    m.AGE,
    m.FLAG AS IS_ACTIVE,
    m.STALE_MEMBER,
    m.ENROLL_DT,
    m.FLIGHT_DT,
    r.TXN_ID,
    r.TXN_DATE,
    r.FEED_DATE,
    r.PARTNER,
    r.MILES_REDEEMED,
    r.STATUS AS REDEMPTION_STATUS
FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED m
LEFT JOIN GOLD_MARTS.FACT_MEMBER_REDEMPTIONS r
    ON m.MEM_ID = r.MEMBER_ID;

-- B. Business Mart: Aggregate Redemption Metrics by Country and Tier
CREATE OR REPLACE VIEW GOLD_MARTS.VW_COUNTRY_TIER_REDEMPTION_SUMMARY AS
SELECT 
    m.COUNTRY,
    m.TIER,
    COUNT(DISTINCT m.MEM_ID)                       AS TOTAL_MEMBERS,
    COUNT(DISTINCT r.TXN_ID)                       AS TOTAL_REDEMPTIONS,
    COALESCE(SUM(r.MILES_REDEEMED), 0)             AS TOTAL_MILES_REDEEMED,
    COALESCE(AVG(r.MILES_REDEEMED), 0)             AS AVG_MILES_PER_TXN,
    COUNT(DISTINCT CASE WHEN m.STALE_MEMBER = 'Y' AND r.TXN_ID IS NOT NULL THEN m.MEM_ID END) AS STALE_MEMBERS_REDEEMING
FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED m
LEFT JOIN GOLD_MARTS.FACT_MEMBER_REDEMPTIONS r
    ON m.MEM_ID = r.MEMBER_ID 
   AND r.STATUS = 'COMPLETED'
GROUP BY m.COUNTRY, m.TIER;
