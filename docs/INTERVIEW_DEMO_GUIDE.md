# Live Interview Walkthrough & Demonstration Guide

This guide provides a structured script and talking points for presenting this solution during a live technical interview with the Incubyte engineering team.

---

## 1. Quick 60-Second Elevator Pitch

> *"To solve SkyPoints' scaling challenge of processing billions of records across flat files and semi-structured partner feeds, I designed a production-grade, Medallion-architecture data pipeline. It features an automated Dead Letter Queue to isolate dirty records (like invalid calendar months or missing keys), vectorised derivation of Age and Stale_Member metrics, a deterministic window-ranking deduplication implementing the 'latest record wins' rule across international relocations, and native semi-structured JSON flattening for 360-degree loyalty analytics. The entire pipeline is fully covered by automated unit and integration tests and is accompanied by production Snowflake DDL."*

---

## 2. Live Demo Execution (Deliverable 6)

In your terminal or IDE, execute:
```bash
python run_demo.py
```

### Demonstration Steps & Talking Points

#### Step 1: Ingestion & Staging with Derived Columns
- **Point out**: The pipe-delimited flat file from page 2 of the assessment is ingested into the raw landing layer.
- **Explain**: Staging automatically normalizes heterogeneous date formats (`YYYYMMDD`, `YYYY-MM-DD`, `MMDDYYYY`) and computes the two required derived columns:
  - **`Age`**: Chronological full years calculated from `DOB`.
  - **`Stale_Member`**: Automatically marked `'Y'` if `CURRENT_DATE - FLIGHT_DT > 90` days (or if the member has never flown).

#### Step 2: Data Quality & Dead Letter Queue (DLQ)
- **Point out**: Rather than letting bad records crash a billion-record pipeline, invalid rows are screened and routed to `dlq_rejected_records`.
- **Showcase**: Highlight the detection of the exact sample data issues from the prompt:
  - **`2021-13-13`**: Quarantined with `INVALID_DATE` (invalid month 13).
  - **`NULL` Name**: Quarantined with `MANDATORY_NULL`.
  - **Future DOB**: Quarantined with `CHRONOLOGY_ERROR`.
  - **Flight before Enrollment**: Quarantined with `CHRONOLOGY_ERROR`.

#### Step 3: Per-Country Target Splitting & "Latest Record Wins"
- **Demonstrate**: Member Elena (`223457`) begins in `table_usa`.
- **Trigger**: Ingest relocation feed where Elena moves to `IND` (India) with an updated flight date and tier upgrade (`PLT`).
- **Showcase**:
  - Elena is automatically purged from `table_usa`.
  - Elena is inserted into `table_india` with her latest tier and flight date.
  - Proves the "latest record wins" rule prevents duplicate profiles across country tables.

#### Step 4: Semi-Structured JSON Redemption Flattening
- **Explain**: The partner airline JSON feed is parsed and flattened into `fact_member_redemptions`.
- **Showcase**: Nested JSON arrays are mapped to relational records with `txn_id`, `member_id`, `partner`, `miles_redeemed`, and `status`.

#### Step 5: Member Loyalty 360 Joins & Analytics
- **Showcase**: The `vw_member_loyalty_360` view seamlessly joins member profiles with their flattened redemptions.
- **Showcase**: Country & Tier summary aggregating total members and total redeemed miles.

---

## 3. Running Automated Tests

Run the test suite to verify all 20 tests pass:
```bash
python -m unittest discover tests -v
```

---

## 4. Anticipated Interview Questions & Answers

### Q1: "How does this pipeline handle billions of records per day without timeouts?"
> *"At billion-record scale, we leverage Snowflake's distributed micro-partitioning and Snowpipe auto-ingestion. Files are chunked in cloud storage (S3/GCS) with Snappy compression. Deduplication uses window functions (`ROW_NUMBER() OVER (PARTITION BY mem_id ORDER BY flight_dt DESC)`) which Snowflake executes via distributed hash-partitioning. In a Spark environment, we would use broadcast joins for small lookup tables and collocated hash joins on `member_id` for redemptions."*

### Q2: "Why use a Dead Letter Queue instead of failing fast?"
> *"At billion-record scale, halting an ETL job on a single corrupted line (like month 13) introduces massive operational latency and violates ingestion SLAs. Isolating invalid rows into a queryable DLQ table enables continuous data flow for valid records while giving data stewards immediate visibility into upstream schema violations."*

### Q3: "How do you prevent race conditions when a member relocates countries concurrently?"
> *"In our Snowflake transformation (`sql/snowflake/04_transform_country_split.sql`), we use atomic `MERGE INTO` operations paired with timestamp ordering (`COALESCE(flight_dt, enroll_dt) DESC`). Additionally, in a high-scale production setting, maintaining a unified Gold dimension `DIM_MEMBERS_UNIFIED` clustered by `(COUNTRY, MEM_ID)` with country views avoids cross-table locks entirely."*
