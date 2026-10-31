"""Transformation engine: Derived columns (Age, Stale_Member) and Latest-Record-Wins deduplication."""

from datetime import date
from typing import Any, Dict, List, Optional

from src.date_utils import compute_age, is_stale_member


def enrich_with_derived_columns(
    record: Dict[str, Any], 
    reference_date: Optional[date] = None
) -> Dict[str, Any]:
    """
    Deliverable 2: Enriches a validated member record with:
    1. Age: Computed from DOB relative to reference date.
    2. Stale_Member: 'Y' if days since Flight_Date > 90 (or Flight_Date is NULL), else 'N'.
    """
    if reference_date is None:
        reference_date = date.today()

    dob = record.get("dob")
    flight_dt = record.get("flight_dt")

    # Derived Column 1: Age
    age = compute_age(dob, reference_date)

    # Derived Column 2: Stale_Member flag
    stale_flag = is_stale_member(flight_dt, reference_date, threshold_days=90)

    enriched = dict(record)
    enriched["age"] = age
    enriched["stale_member"] = stale_flag

    return enriched


def apply_latest_record_wins(records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Deliverable 3: Deduplicates records by mem_id applying the 'Latest Record Wins' rule.
    When a member has moved countries or has multiple updates across files/batches,
    the record with the latest activity date takes precedence.
    
    Ranking order:
    1. Latest Flight_Date
    2. Latest Enrollment_Date
    3. File line number / arrival order
    """
    grouped_by_member: Dict[str, List[Dict[str, Any]]] = {}

    for rec in records:
        mid = rec["mem_id"]
        if mid not in grouped_by_member:
            grouped_by_member[mid] = []
        grouped_by_member[mid].append(rec)

    winning_records: List[Dict[str, Any]] = []

    for mid, member_history in grouped_by_member.items():
        if len(member_history) == 1:
            winning_records.append(member_history[0])
            continue

        # Sort candidate records: latest date wins
        def sort_key(r: Dict[str, Any]):
            flight_dt = r.get("flight_dt")
            enroll_dt = r.get("enroll_dt")
            # Convert date to ordinal int or -1 if None
            f_val = flight_dt.toordinal() if flight_dt else -1
            e_val = enroll_dt.toordinal() if enroll_dt else -1
            line_val = r.get("_line_num", 0)
            return (f_val, e_val, line_val)

        sorted_records = sorted(member_history, key=sort_key, reverse=True)
        winning_records.append(sorted_records[0])

    return winning_records
