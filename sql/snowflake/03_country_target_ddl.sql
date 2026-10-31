-- ============================================================================
-- Incubyte Technical Assessment: SkyPoints Loyalty Data Pipeline
-- Deliverable 1: Snowflake Country-Specific Target Tables DDL (Gold Layer)
-- Creates physical target tables per country as specified in the requirements:
-- "All members related to India will go to Table_India, and so on for each country."
-- ============================================================================

USE DATABASE SKYPOINTS_DB;
USE SCHEMA GOLD_MARTS;

-- Template schema used for country target tables:
-- Each table stores the definitive, up-to-date member profile for that country.
-- Primary key: MEM_ID (enforces 1 record per member across the loyalty system).

-- 1. Table_India
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_INDIA (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL DEFAULT 'IND',
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_INDIA PRIMARY KEY (MEM_ID)
)
CLUSTER BY (MEM_ID)
COMMENT = 'Gold loyalty member profiles for India';

-- 2. Table_USA
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_USA (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL DEFAULT 'USA',
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_USA PRIMARY KEY (MEM_ID)
)
CLUSTER BY (MEM_ID)
COMMENT = 'Gold loyalty member profiles for United States';

-- 3. Table_Canada
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_CANADA (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL DEFAULT 'CAN',
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_CANADA PRIMARY KEY (MEM_ID)
)
CLUSTER BY (MEM_ID)
COMMENT = 'Gold loyalty member profiles for Canada';

-- 4. Table_Philippines
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_PHILIPPINES (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL DEFAULT 'PHIL',
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_PHILIPPINES PRIMARY KEY (MEM_ID)
)
CLUSTER BY (MEM_ID)
COMMENT = 'Gold loyalty member profiles for Philippines';

-- 5. Table_Australia
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_AUSTRALIA (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL DEFAULT 'AU',
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_AUSTRALIA PRIMARY KEY (MEM_ID)
)
CLUSTER BY (MEM_ID)
COMMENT = 'Gold loyalty member profiles for Australia';

-- 6. Table_Other_Countries (Default catch-all for new/international locations)
CREATE OR REPLACE TABLE GOLD_MARTS.TABLE_OTHER_COUNTRIES (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL,
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_TABLE_OTHER PRIMARY KEY (MEM_ID)
)
CLUSTER BY (COUNTRY, MEM_ID)
COMMENT = 'Catch-all loyalty member profiles for unlisted countries';

-- ----------------------------------------------------------------------------
-- Billion-Record Scalability Alternative:
-- Partitioned Unified Gold Mart + Dynamic Country Views
-- (Avoids managing hundreds of discrete physical tables in Snowflake)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE GOLD_MARTS.DIM_MEMBERS_UNIFIED (
    MEM_ID               VARCHAR(18)  NOT NULL,
    NAME                 VARCHAR(255) NOT NULL,
    ENROLL_DT            DATE         NOT NULL,
    FLIGHT_DT            DATE,
    TIER                 VARCHAR(5),
    AGENT_NAME           VARCHAR(255),
    STATE                VARCHAR(5),
    COUNTRY              VARCHAR(10)  NOT NULL,
    POST_CODE            INT,
    DOB                  DATE,
    FLAG                 CHAR(1),
    AGE                  NUMBER(3, 0),
    STALE_MEMBER         CHAR(1)      NOT NULL,
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_FILE         VARCHAR(255),
    CONSTRAINT PK_MEMBERS_UNIFIED PRIMARY KEY (MEM_ID)
)
CLUSTER BY (COUNTRY, MEM_ID)
COMMENT = 'Unified Gold member profile table with automatic micro-partitioning by Country';

-- Virtual Country Views over Unified Gold Table:
CREATE OR REPLACE VIEW GOLD_MARTS.VW_TABLE_INDIA AS 
    SELECT * FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED WHERE COUNTRY IN ('IND', 'INDIA');

CREATE OR REPLACE VIEW GOLD_MARTS.VW_TABLE_USA AS 
    SELECT * FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED WHERE COUNTRY IN ('USA', 'US');

CREATE OR REPLACE VIEW GOLD_MARTS.VW_TABLE_CANADA AS 
    SELECT * FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED WHERE COUNTRY IN ('CAN', 'CANADA');

CREATE OR REPLACE VIEW GOLD_MARTS.VW_TABLE_PHILIPPINES AS 
    SELECT * FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED WHERE COUNTRY IN ('PHIL', 'PHL', 'PH');

CREATE OR REPLACE VIEW GOLD_MARTS.VW_TABLE_AUSTRALIA AS 
    SELECT * FROM GOLD_MARTS.DIM_MEMBERS_UNIFIED WHERE COUNTRY IN ('AU', 'AUS', 'AUSTRALIA');
