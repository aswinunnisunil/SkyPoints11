"""Unit tests for semi-structured JSON redemption feed parsing."""

import os
import unittest

from src.config import RAW_DATA_DIR
from src.ingestion import parse_json_redemption_feed


class TestJsonParser(unittest.TestCase):

    def test_parse_redemptions_json(self):
        json_file = os.path.join(RAW_DATA_DIR, "skypoints_redemptions_20240115_12000000.json")
        flattened = parse_json_redemption_feed(json_file)

        self.assertGreater(len(flattened), 0)
        # Check first record from PDF sample
        rx1 = next((r for r in flattened if r["txn_id"] == "RX10091"), None)
        self.assertIsNotNone(rx1)
        self.assertEqual(rx1["member_id"], "223457")
        self.assertEqual(rx1["feed_date"], "20240115")
        self.assertEqual(rx1["txn_date"], "20240110")
        self.assertEqual(rx1["partner"], "AeroLink")
        self.assertEqual(rx1["miles_redeemed"], 12000)
        self.assertEqual(rx1["status"], "COMPLETED")

        # Check second record
        rx2 = next((r for r in flattened if r["txn_id"] == "RX10092"), None)
        self.assertIsNotNone(rx2)
        self.assertEqual(rx2["status"], "PENDING")
        self.assertEqual(rx2["miles_redeemed"], 5000)


if __name__ == "__main__":
    unittest.main()
