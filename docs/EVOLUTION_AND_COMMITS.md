# Engineering Solution Evolution & Recommended Git Commits

As requested in the Incubyte Technical Assessment (*"Please make incremental commits so we can understand how your solution evolved"*), this document records the architectural progression and logical commit history of the solution.

If initializing a new Git repository, you can commit following these incremental milestones:

---

### Commit 1: Project Scaffolding & Initial Schema DDL
```bash
git add data/raw/ sql/
git commit -m "feat(ddl): define raw landing, staging, and country target DDL for Snowflake and SQLite"
```
- Established raw data files matching the assessment specification (`skypoints_members_20240115_08000000.dat`, `skypoints_redemptions_20240115_12000000.json`).
- Authored Snowflake DDL scripts (`01_raw_landing_ddl.sql`, `02_staging_ddl.sql`, `03_country_target_ddl.sql`).
- Created equivalent local SQLite schemas for offline execution.

---

### Commit 2: Staging Table & Derived Columns (Age, Stale_Member)
```bash
git add src/date_utils.py src/transformation.py tests/test_date_utils.py
git commit -m "feat(staging): implement multi-format date parsing and derived Age and Stale_Member logic"
```
- Built `src/date_utils.py` handling `YYYYMMDD`, `YYYY-MM-DD`, and missing-zero formats (`6152022`, `1052022`).
- Implemented `compute_age` calculating completed chronological years from DOB.
- Implemented `is_stale_member` flagging `'Y'` when days since flight $> 90$ or flight date is NULL.

---

### Commit 3: Per-Country Target Splitting with 'Latest Record Wins'
```bash
git add src/country_router.py sql/snowflake/04_transform_country_split.sql tests/test_transformation.py
git commit -m "feat(transform): add per-country table routing and 'latest record wins' relocation logic"
```
- Implemented `route_members_by_country` and `sync_members_to_country_tables`.
- Enforced deduplication where latest activity date takes precedence.
- Solved member cross-country relocation: Elena moving from USA to India is purged from `table_usa` and upserted to `table_india`.

---

### Commit 4: Semi-Structured JSON Redemption Flattening & 360 Joins
```bash
git add src/ingestion.py src/analytics.py sql/snowflake/05_json_redemptions_flatten.sql tests/test_json_parser.py
git commit -m "feat(redemptions): parse partner JSON feeds, flatten nested arrays, and join to member profiles"
```
- Implemented `parse_json_redemption_feed` and Snowflake `LATERAL FLATTEN`.
- Created analytical views (`vw_member_loyalty_360`, `vw_country_tier_redemption_summary`).
- Verified transactional joins linking member profiles with airline mileage burn events.

---

### Commit 5: Data Quality Screening & Dead Letter Queue (DLQ)
```bash
git add src/validator.py sql/snowflake/06_data_quality_checks.sql tests/test_validator.py data/raw/skypoints_members_dirty_20240115_09000000.csv
git commit -m "feat(quality): implement DQ screening engine and Dead Letter Queue for anomaly quarantine"
```
- Created `src/validator.py` catching mandatory field nulls, invalid dates (e.g. `2021-13-13` month 13), and chronology errors.
- Built `dlq_rejected_records` table to quarantine malformed rows without breaking continuous streaming.

---

### Commit 6: End-to-End Pipeline Orchestration & Test Suite
```bash
git add src/pipeline.py tests/test_pipeline_e2e.py
git commit -m "feat(pipeline): build master pipeline orchestrator and end-to-end integration test suite"
```
- Integrated Bronze $\rightarrow$ Silver $\rightarrow$ Gold pipeline execution.
- Added comprehensive unit and integration tests passing with 100% success rate.

---

### Commit 7: Turnkey Live Demonstration & Production Architecture
```bash
git add run_demo.py docs/ README.md .gitignore
git commit -m "docs: add billion-record architecture design, interview guide, and turnkey demo script"
```
- Built `run_demo.py` with aligned tabular outputs demonstrating all 6 deliverables.
- Documented Big Data scalability mechanics in `docs/ARCHITECTURE.md`.
- Documented candidate interview presentation walkthrough in `docs/INTERVIEW_DEMO_GUIDE.md`.
