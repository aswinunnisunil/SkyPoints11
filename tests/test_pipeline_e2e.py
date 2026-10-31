"""End-to-end integration tests for SkyPoints Loyalty Data Pipeline."""

import os
import tempfile
import unittest

from src.analytics import get_country_redemption_summary, get_member_loyalty_360
from src.config import RAW_DATA_DIR
from src.pipeline import SkyPointsPipeline


class TestPipelineE2E(unittest.TestCase):

    def setUp(self):
        # Create unique temp db for isolation
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = os.path.join(self.temp_dir.name, "test_loyalty.db")
        self.pipeline = SkyPointsPipeline(db_path=self.db_path)

    def tearDown(self):
        self.pipeline.close()
        self.temp_dir.cleanup()

    def test_end_to_end_pipeline(self):
        # 1. Ingest clean flat file feed (from assessment page 2)
        flat_file = os.path.join(RAW_DATA_DIR, "skypoints_members_20240115_08000000.dat")
        summary_flat = self.pipeline.ingest_member_file(flat_file)
        self.assertEqual(summary_flat["total_records"], 10)
        self.assertEqual(summary_flat["valid_records"], 10)
        self.assertEqual(summary_flat["quarantined_records"], 0)

        cursor = self.pipeline.conn.cursor()

        # Verify Elena (223457) is initially in table_usa
        cursor.execute("SELECT mem_id, name, country, stale_member FROM table_usa WHERE mem_id = '223457'")
        elena = cursor.fetchone()
        self.assertIsNotNone(elena)
        self.assertEqual(elena[1], "Elena")
        self.assertEqual(elena[2], "USA")
        self.assertEqual(elena[3], "Y")  # 2012 flight is > 90 days ago

        # Verify Ravi (223458) is in table_india
        cursor.execute("SELECT mem_id, name, country FROM table_india WHERE mem_id = '223458'")
        ravi = cursor.fetchone()
        self.assertIsNotNone(ravi)
        self.assertEqual(ravi[1], "Ravi")
        self.assertEqual(ravi[2], "IND")

        # 2. Ingest dirty file feed (testing DQ & Dead Letter Queue)
        dirty_file = os.path.join(RAW_DATA_DIR, "skypoints_members_dirty_20240115_09000000.csv")
        summary_dirty = self.pipeline.ingest_member_file(dirty_file)
        self.assertGreater(summary_dirty["quarantined_records"], 0)

        # Check DLQ recorded month 13 error for Jonnathan (2021-13-13)
        cursor.execute("SELECT error_category, error_message FROM dlq_rejected_records WHERE raw_record LIKE '%Jonnathan%'")
        dlq_jonnathan = cursor.fetchone()
        self.assertIsNotNone(dlq_jonnathan)
        self.assertEqual(dlq_jonnathan[0], "INVALID_DATE")

        # Check DLQ recorded TimeTraveler error
        cursor.execute("SELECT error_category, error_message FROM dlq_rejected_records WHERE raw_record LIKE '%TimeTraveler%'")
        dlq_tt = cursor.fetchone()
        self.assertIsNotNone(dlq_tt)
        self.assertEqual(dlq_tt[0], "CHRONOLOGY_ERROR")

        # 3. Ingest Relocation file (testing 'Latest Record Wins' cross-country update)
        relocation_file = os.path.join(RAW_DATA_DIR, "skypoints_members_relocation_20240116_10000000.dat")
        summary_reloc = self.pipeline.ingest_member_file(relocation_file)
        self.assertEqual(summary_reloc["valid_records"], 2)

        # Crucial check: Elena has moved from USA to IND!
        # She must now exist in table_india:
        cursor.execute("SELECT mem_id, country, tier, agent_name FROM table_india WHERE mem_id = '223457'")
        elena_ind = cursor.fetchone()
        self.assertIsNotNone(elena_ind)
        self.assertEqual(elena_ind[1], "IND")
        self.assertEqual(elena_ind[2], "PLT")  # Tier upgraded to PLT
        self.assertEqual(elena_ind[3], "Vikram")

        # She must NO LONGER exist in table_usa!
        cursor.execute("SELECT mem_id FROM table_usa WHERE mem_id = '223457'")
        elena_usa = cursor.fetchone()
        self.assertIsNone(elena_usa, "Elena moved to India, so she must be purged from table_usa!")

        # 4. Ingest JSON redemptions feed
        json_file = os.path.join(RAW_DATA_DIR, "skypoints_redemptions_20240115_12000000.json")
        summary_json = self.pipeline.ingest_redemptions_file(json_file)
        self.assertEqual(summary_json["total_transactions"], 6)

        cursor.execute("SELECT COUNT(*) FROM fact_member_redemptions")
        redemption_count = cursor.fetchone()[0]
        self.assertEqual(redemption_count, 6)

        # 5. Verify Member Loyalty 360 joins
        loyalty_360 = get_member_loyalty_360(self.pipeline.conn)
        self.assertGreater(len(loyalty_360), 0)

        # Elena's redemptions joined with her new India profile
        elena_txns = [r for r in loyalty_360 if r["mem_id"] == "223457" and r["txn_id"]]
        self.assertEqual(len(elena_txns), 2)
        self.assertEqual(elena_txns[0]["country"], "IND")

        # 6. Verify Country summary aggregation
        country_summary = get_country_redemption_summary(self.pipeline.conn)
        self.assertGreater(len(country_summary), 0)


if __name__ == "__main__":
    unittest.main()
