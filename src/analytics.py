"""Analytics module: persists flattened redemptions and queries joins with member profiles."""

import sqlite3
from typing import Any, Dict, List


def save_flattened_redemptions(
    conn: sqlite3.Connection, 
    redemptions: List[Dict[str, Any]]
) -> int:
    """Inserts or updates flattened partner redemption records into the analytical fact table."""
    cursor = conn.cursor()
    inserted_count = 0

    for r in redemptions:
        cursor.execute(
            """
            INSERT OR REPLACE INTO fact_member_redemptions (
                txn_id, member_id, feed_date, txn_date, partner, miles_redeemed, status, _source_file, ingestion_timestamp
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """,
            (
                r["txn_id"],
                r["member_id"],
                r["feed_date"],
                r["txn_date"],
                r["partner"],
                r["miles_redeemed"],
                r["status"],
                r.get("_source_file"),
            )
        )
        inserted_count += 1

    conn.commit()
    return inserted_count


def get_member_loyalty_360(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    """Joins member profile tables with flattened redemptions for a complete 360-degree view."""
    cursor = conn.cursor()
    query = """
    SELECT 
        m.mem_id,
        m.name,
        m.country,
        m.tier,
        m.age,
        m.stale_member,
        r.txn_id,
        r.txn_date,
        r.partner,
        r.miles_redeemed,
        r.status AS redemption_status
    FROM vw_all_active_members m
    LEFT JOIN fact_member_redemptions r
        ON m.mem_id = r.member_id
    ORDER BY m.country, m.mem_id, r.txn_date DESC
    """
    cursor.execute(query)
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def get_country_redemption_summary(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    """Aggregates mileage redemptions grouped by country and loyalty tier."""
    cursor = conn.cursor()
    query = """
    SELECT 
        m.country,
        m.tier,
        COUNT(DISTINCT m.mem_id) AS total_members,
        COUNT(r.txn_id) AS total_redemptions,
        COALESCE(SUM(r.miles_redeemed), 0) AS total_miles_redeemed,
        COALESCE(AVG(r.miles_redeemed), 0) AS avg_miles_per_txn
    FROM vw_all_active_members m
    LEFT JOIN fact_member_redemptions r
        ON m.mem_id = r.member_id AND r.status = 'COMPLETED'
    GROUP BY m.country, m.tier
    ORDER BY total_miles_redeemed DESC
    """
    cursor.execute(query)
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]
