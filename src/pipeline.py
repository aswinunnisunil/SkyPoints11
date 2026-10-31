"""Master ETL Pipeline Orchestrator for SkyPoints Loyalty Data Engine."""

import os
import sqlite3
from typing import Any, Dict, List, Optional

from src.analytics import save_flattened_redemptions
from src.config import BASE_DIR, DB_PATH, OUTPUT_DATA_DIR
from src.country_router import sync_members_to_country_tables
from src.ingestion import (
    parse_csv_member_file,
    parse_json_redemption_feed,
    parse_pipe_delimited_file,
)
from src.transformation import apply_latest_record_wins, enrich_with_derived_columns
from src.validator import validate_member_record


class SkyPointsPipeline:
    """End-to-end orchestrator for SkyPoints loyalty data ingestion, validation, and transformations."""

    def __init__(self, db_path: str = DB_PATH):
        self.db_path = db_path
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self._init_database()

    def _init_database(self) -> None:
        """Initializes database tables, schemas, and analytical views."""
        schema_file = os.path.join(BASE_DIR, "sql", "local_sqlite", "schema.sql")
        views_file = os.path.join(BASE_DIR, "sql", "local_sqlite", "views_and_queries.sql")

        with open(schema_file, "r", encoding="utf-8") as f:
            self.conn.executescript(f.read())

        with open(views_file, "r", encoding="utf-8") as f:
            self.conn.executescript(f.read())
        self.conn.commit()

    def ingest_member_file(self, file_path: str) -> Dict[str, Any]:
        """
        Ingests a member profile file (pipe-delimited or CSV), validates each record,
        quarantines bad rows to DLQ, enriches valid rows, and stages them.
        """
        cursor = self.conn.cursor()
        filename = os.path.basename(file_path)

        if file_path.endswith(".csv"):
            generator = parse_csv_member_file(file_path)
        else:
            generator = parse_pipe_delimited_file(file_path)

        total_read = 0
        valid_records = []
        quarantined_count = 0

        for raw_rec in generator:
            total_read += 1

            # 1. Store verbatim in bronze raw landing
            cursor.execute(
                """
                INSERT INTO raw_member_profiles (record_type, raw_line, source_file_name, file_row_number)
                VALUES ('D', ?, ?, ?)
                """,
                (raw_rec.get("_raw_line", ""), filename, raw_rec.get("_line_num", 0))
            )

            # 2. Validate against business rules & data quality
            cleansed, errors = validate_member_record(raw_rec)

            if errors:
                quarantined_count += 1
                for err in errors:
                    cursor.execute(
                        """
                        INSERT INTO dlq_rejected_records (
                            source_file_name, file_row_number, raw_record, error_category, error_field, error_message
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        (
                            filename,
                            raw_rec.get("_line_num", 0),
                            raw_rec.get("_raw_line", ""),
                            err.category,
                            err.field,
                            err.message,
                        )
                    )
            else:
                # 3. Enrich with derived columns: Age and Stale_Member
                cleansed["_source_file"] = filename
                cleansed["_line_num"] = raw_rec.get("_line_num", 0)
                enriched = enrich_with_derived_columns(cleansed)
                valid_records.append(enriched)

                # 4. Save to Silver Staging table
                cursor.execute(
                    """
                    INSERT INTO staging_members (
                        name, mem_id, enroll_dt, flight_dt, tier, agent_name, state, country,
                        post_code, dob, flag, age, stale_member, _source_file, _source_row_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        enriched["name"],
                        enriched["mem_id"],
                        enriched["enroll_dt"].isoformat() if enriched.get("enroll_dt") else None,
                        enriched["flight_dt"].isoformat() if enriched.get("flight_dt") else None,
                        enriched.get("tier"),
                        enriched.get("agent_name"),
                        enriched.get("state"),
                        enriched.get("country"),
                        enriched.get("post_code"),
                        enriched["dob"].isoformat() if enriched.get("dob") else None,
                        enriched.get("flag"),
                        enriched.get("age"),
                        enriched.get("stale_member"),
                        filename,
                        raw_rec.get("_line_num", 0),
                    )
                )

        self.conn.commit()

        # 5. Apply "Latest Record Wins" deduplication
        deduplicated = apply_latest_record_wins(valid_records)

        # 6. Route to per-country target tables
        country_counts = sync_members_to_country_tables(self.conn, deduplicated)

        return {
            "file": filename,
            "total_records": total_read,
            "valid_records": len(valid_records),
            "quarantined_records": quarantined_count,
            "deduplicated_active": len(deduplicated),
            "country_distribution": country_counts,
        }

    def ingest_redemptions_file(self, file_path: str) -> Dict[str, Any]:
        """
        Parses partner JSON feed, stores raw payload, flattens redemptions,
        and loads into the analytical fact table.
        """
        cursor = self.conn.cursor()
        filename = os.path.basename(file_path)

        with open(file_path, "r", encoding="utf-8") as f:
            raw_text = f.read()

        cursor.execute(
            "INSERT INTO raw_redemption_feeds (raw_payload, source_file_name) VALUES (?, ?)",
            (raw_text, filename)
        )
        self.conn.commit()

        flattened = parse_json_redemption_feed(file_path)
        saved_count = save_flattened_redemptions(self.conn, flattened)

        total_miles = sum(r["miles_redeemed"] for r in flattened if r["status"] == "COMPLETED")

        return {
            "file": filename,
            "total_transactions": len(flattened),
            "saved_records": saved_count,
            "total_completed_miles": total_miles,
        }

    def close(self) -> None:
        """Closes the active database connection."""
        self.conn.close()
