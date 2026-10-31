"""Country routing logic: splits members into country-specific tables and synchronizes relocations."""

import sqlite3
from typing import Any, Dict, List, Set

from src.config import COUNTRY_TABLE_MAPPING, DEFAULT_COUNTRY_TABLE


def resolve_country_table(country_code: str) -> str:
    """Resolves a raw country string or code into the corresponding target table name."""
    if not country_code:
        return DEFAULT_COUNTRY_TABLE
    cleaned = country_code.strip().upper()
    return COUNTRY_TABLE_MAPPING.get(cleaned, DEFAULT_COUNTRY_TABLE)


def route_members_by_country(records: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Groups a list of member records by their designated country target table.
    Returns:
        Dict mapping table_name -> list of member records.
    """
    routed: Dict[str, List[Dict[str, Any]]] = {}
    for rec in records:
        country = rec.get("country", "")
        table_name = resolve_country_table(country)
        if table_name not in routed:
            routed[table_name] = []
        routed[table_name].append(rec)
    return routed


def sync_members_to_country_tables(
    conn: sqlite3.Connection, 
    records: List[Dict[str, Any]]
) -> Dict[str, int]:
    """
    Persists member records into their respective country target tables.
    Enforces the 'Latest Record Wins' rule across country tables:
    If a member moved to a new country, they are upserted into the new country table
    and deleted from any prior country table so no stale duplicates exist.
    """
    cursor = conn.cursor()
    all_country_tables = list(set(COUNTRY_TABLE_MAPPING.values())) + [DEFAULT_COUNTRY_TABLE]
    counts: Dict[str, int] = {tbl: 0 for tbl in all_country_tables}

    routed = route_members_by_country(records)

    for target_table, member_list in routed.items():
        for rec in member_list:
            mid = rec["mem_id"]

            # Step 1: Remove member from all OTHER country tables (member relocation handling)
            for other_table in all_country_tables:
                if other_table != target_table:
                    cursor.execute(
                        "DELETE FROM {} WHERE mem_id = ?".format(other_table), 
                        (mid,)
                    )

            # Step 2: Upsert into current country table
            enroll_dt_str = rec["enroll_dt"].isoformat() if rec.get("enroll_dt") else None
            flight_dt_str = rec["flight_dt"].isoformat() if rec.get("flight_dt") else None
            dob_str = rec["dob"].isoformat() if rec.get("dob") else None

            cursor.execute(
                """
                INSERT OR REPLACE INTO {table} (
                    mem_id, name, enroll_dt, flight_dt, tier, agent_name, state, country,
                    post_code, dob, flag, age, stale_member, _source_file, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """.format(table=target_table),
                (
                    mid,
                    rec["name"],
                    enroll_dt_str,
                    flight_dt_str,
                    rec.get("tier"),
                    rec.get("agent_name"),
                    rec.get("state"),
                    rec.get("country"),
                    rec.get("post_code"),
                    dob_str,
                    rec.get("flag"),
                    rec.get("age"),
                    rec.get("stale_member"),
                    rec.get("_source_file"),
                )
            )
            counts[target_table] += 1

    conn.commit()
    return counts
