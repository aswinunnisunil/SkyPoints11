# SkyPoints Loyalty Platform: Data Dictionary & Quality Rules

## 1. Member Profile Feed Specification

### File Naming Convention
- **Format**: `skypoints_members_YYYYMMDD_HHMMSSTT.<ext>`
- **Delimiters**: Pipe (`|`) separated records
- **Record Types**:
  - `|H|` Header Record
  - `|D|` Detail Record

### Schema Definition & Source Mappings

| Position | Source Field | Target Column | Data Type | Mandatory | Key Column | Description & Validation Rules |
|:---:|:---|:---|:---|:---:|:---:|:---|
| 1 | Member Name | `NAME` | VARCHAR(255) | **Y** | **Y** | Primary identity. Must not be empty, NULL, or whitespace. |
| 2 | Member ID | `MEM_ID` | VARCHAR(18) | **Y** | N | Unique SkyPoints loyalty identifier. Mandatory. |
| 3 | Enrollment Date | `ENROLL_DT` | DATE | **Y** | N | Date enrolled (YYYYMMDD, YYYY-MM-DD, MMDDYYYY). Cannot be NULL. Cannot be in the future. |
| 4 | Last Flight Date | `FLIGHT_DT` | DATE | N | N | Most recent flight date. Cannot be before `ENROLL_DT`. Cannot be in future. |
| 5 | Tier Code | `TIER` | VARCHAR(5) | N | N | Loyalty tier (`SLV`, `GLD`, `PLT`). Defaults to `SLV`. |
| 6 | Agent Name | `AGENT_NAME` | VARCHAR(255) | N | N | Onboarding booking agent or channel representative. |
| 7 | State | `STATE` | VARCHAR(5) | N | N | State or province abbreviation (e.g. `CA`, `TN`, `ON`). |
| 8 | Country | `COUNTRY` | VARCHAR(10) | N | N | Country code (e.g. `IND`, `USA`, `CAN`, `PHIL`, `AU`). |
| 9 | Post Code | `POST_CODE` | INTEGER | N | N | Postal or ZIP code. Nullable. |
| 10 | Date of Birth | `DOB` | DATE | N | N | Birthdate. Must be `< CURRENT_DATE` and `<= ENROLL_DT`. |
| 11 | Active Member | `FLAG` | CHAR(1) | N | N | Member activity status (`A` = Active, `I` = Inactive). |

---

## 2. Derived Columns (Deliverable 2)

### A. `AGE` (INTEGER)
- **Definition**: Exact chronological age in completed years from `DOB` to current evaluation date.
- **Computation**:
  - `DATEDIFF('year', DOB, CURRENT_DATE) - IFF(DATEADD('year', DATEDIFF('year', DOB, CURRENT_DATE), DOB) > CURRENT_DATE, 1, 0)`
  - Returns `NULL` if `DOB` is `NULL` or invalid.

### B. `STALE_MEMBER` (CHAR(1))
- **Definition**: Identifies members who have not flown recently or have never taken a flight.
- **Rule**:
  - If `FLIGHT_DT IS NULL` $\rightarrow$ `'Y'` (Stale)
  - If `(CURRENT_DATE - FLIGHT_DT) > 90` days $\rightarrow$ `'Y'` (Stale)
  - If `(CURRENT_DATE - FLIGHT_DT) <= 90` days $\rightarrow$ `'N'` (Active / Not Stale)

---

## 3. Partner Mileage Redemption JSON Feed (Deliverable 4)

### File Naming Convention
- **Format**: `skypoints_redemptions_YYYYMMDD_HHMMSSTT.json`

### Field Specifications & Flattened Mapping

| JSON Path | Target Column | Data Type | Mandatory | Description |
|:---|:---|:---|:---:|:---|
| `member_id` | `MEMBER_ID` | VARCHAR(18) | **Y** | Foreign key linking to `MEM_ID` in member tables. |
| `feed_date` | `FEED_DATE` | DATE | **Y** | Transmission date of partner airline feed (YYYYMMDD). |
| `redemptions[].txn_id` | `TXN_ID` | VARCHAR(30) | **Y** | Unique transaction identifier (Primary Key). |
| `redemptions[].txn_date` | `TXN_DATE` | DATE | **Y** | Date transaction took place (YYYYMMDD). |
| `redemptions[].partner` | `PARTNER` | VARCHAR(100) | **Y** | Partner airline or lounge partner name (e.g. `AeroLink`). |
| `redemptions[].miles_redeemed`| `MILES_REDEEMED`| NUMBER(12, 0)| **Y** | Number of loyalty miles redeemed. Must be $\ge 0$. |
| `redemptions[].status` | `STATUS` | VARCHAR(20) | **Y** | Status (`COMPLETED`, `PENDING`, `CANCELLED`). |

---

## 4. Data Quality Rules & Anomaly Handling (Deliverable 5)

| Validation Category | Failure Condition | Target Action | DLQ Error Code |
|:---|:---|:---|:---|
| **Mandatory Field** | `NAME IS NULL`, `MEM_ID IS NULL`, or `ENROLL_DT IS NULL` | Quarantined to DLQ | `MANDATORY_NULL` |
| **Invalid Date** | Date unparseable (e.g. `2021-13-13` month 13) | Quarantined to DLQ | `INVALID_DATE` |
| **Future Date** | `DOB > CURRENT_DATE` or `ENROLL_DT > CURRENT_DATE` | Quarantined to DLQ | `CHRONOLOGY_ERROR` |
| **Chronological Inversion**| `FLIGHT_DT < ENROLL_DT` or `DOB > ENROLL_DT` | Quarantined to DLQ | `CHRONOLOGY_ERROR` |
| **Domain Violation** | `FLAG NOT IN ('A', 'I')` | Quarantined to DLQ | `DOMAIN_VIOLATION` |
| **Duplicate Key** | Multiple records for same `MEM_ID` in batch | Resolved via Latest Record Wins | `RESOLVED_DEDUPE` |
