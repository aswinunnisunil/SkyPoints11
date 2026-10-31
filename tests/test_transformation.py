"""Unit tests for staging enrichment and 'Latest Record Wins' deduplication."""

import unittest
from datetime import date

from src.transformation import apply_latest_record_wins, enrich_with_derived_columns


class TestTransformation(unittest.TestCase):

    def setUp(self):
        self.ref_date = date(2024, 1, 15)

    def test_enrich_derived_columns(self):
        record = {
            "name": "Elena",
            "mem_id": "223457",
            "enroll_dt": date(2010, 10, 12),
            "flight_dt": date(2012, 10, 13),
            "dob": date(1985, 5, 3),
        }
        enriched = enrich_with_derived_columns(record, reference_date=self.ref_date)
        # Age on 2024-01-15: 38
        self.assertEqual(enriched["age"], 38)
        # Flight in 2012 is > 90 days ago: Stale 'Y'
        self.assertEqual(enriched["stale_member"], "Y")

    def test_latest_record_wins_when_member_moves_country(self):
        # Elena initially in USA (flight date 2012-10-13)
        old_record = {
            "name": "Elena",
            "mem_id": "223457",
            "enroll_dt": date(2010, 10, 12),
            "flight_dt": date(2012, 10, 13),
            "country": "USA",
            "_line_num": 1,
        }
        # Elena later updates profile and moves to IND (flight date 2024-01-10)
        new_record = {
            "name": "Elena",
            "mem_id": "223457",
            "enroll_dt": date(2010, 10, 12),
            "flight_dt": date(2024, 1, 10),
            "country": "IND",
            "_line_num": 2,
        }

        # Provide in reverse order to ensure sorting logic takes precedence
        records = [old_record, new_record]
        winning = apply_latest_record_wins(records)

        self.assertEqual(len(winning), 1)
        self.assertEqual(winning[0]["mem_id"], "223457")
        self.assertEqual(winning[0]["country"], "IND")
        self.assertEqual(winning[0]["flight_dt"], date(2024, 1, 10))

    def test_latest_record_wins_fallback_to_enrollment_date(self):
        # Two records without flight dates; newer enrollment date wins
        rec1 = {
            "name": "Sam",
            "mem_id": "101",
            "enroll_dt": date(2020, 1, 1),
            "flight_dt": None,
            "country": "CAN",
            "_line_num": 1,
        }
        rec2 = {
            "name": "Sam",
            "mem_id": "101",
            "enroll_dt": date(2022, 6, 15),
            "flight_dt": None,
            "country": "USA",
            "_line_num": 2,
        }

        winning = apply_latest_record_wins([rec1, rec2])
        self.assertEqual(len(winning), 1)
        self.assertEqual(winning[0]["country"], "USA")
        self.assertEqual(winning[0]["enroll_dt"], date(2022, 6, 15))


if __name__ == "__main__":
    unittest.main()
