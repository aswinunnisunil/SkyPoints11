"""Unit tests for data validation rules and anomaly detection."""

import unittest
from datetime import date

from src.validator import validate_member_record


class TestValidator(unittest.TestCase):

    def setUp(self):
        self.ref_date = date(2024, 1, 15)

    def test_valid_record(self):
        record = {
            "name": "Elena",
            "mem_id": "223457",
            "enroll_dt": "20101012",
            "flight_dt": "20121013",
            "tier": "GLD",
            "agent_name": "Sam",
            "state": "CA",
            "country": "USA",
            "dob": "03051985",
            "flag": "A",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertEqual(len(errors), 0)
        self.assertIsNotNone(cleansed)
        self.assertEqual(cleansed["name"], "Elena")
        self.assertEqual(cleansed["mem_id"], "223457")
        self.assertEqual(cleansed["enroll_dt"], date(2010, 10, 12))

    def test_missing_mandatory_name(self):
        record = {
            "name": "",
            "mem_id": "223457",
            "enroll_dt": "20101012",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0].category, "MANDATORY_NULL")
        self.assertEqual(errors[0].field, "name")

    def test_missing_mandatory_member_id(self):
        record = {
            "name": "Elena",
            "mem_id": "NULL",
            "enroll_dt": "20101012",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertEqual(len(errors), 1)
        self.assertEqual(errors[0].category, "MANDATORY_NULL")
        self.assertEqual(errors[0].field, "mem_id")

    def test_invalid_enrollment_date_month_13(self):
        # The exact prompt error: '2021-13-13'
        record = {
            "name": "Jonnathan",
            "mem_id": "223459",
            "enroll_dt": "2021-13-13",
            "country": "USA",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertTrue(any(e.category == "INVALID_DATE" for e in errors))

    def test_chronology_flight_before_enrollment(self):
        record = {
            "name": "TimeTraveler",
            "mem_id": "999",
            "enroll_dt": "2022-05-01",
            "flight_dt": "2020-01-01",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertTrue(any(e.category == "CHRONOLOGY_ERROR" for e in errors))

    def test_chronology_dob_in_future(self):
        record = {
            "name": "FutureMan",
            "mem_id": "1000",
            "enroll_dt": "2022-01-01",
            "dob": "2035-01-01",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertTrue(any(e.category == "CHRONOLOGY_ERROR" for e in errors))

    def test_domain_violation_flag(self):
        record = {
            "name": "TestUser",
            "mem_id": "1001",
            "enroll_dt": "2022-01-01",
            "flag": "INVALID_FLAG_X",
        }
        cleansed, errors = validate_member_record(record, reference_date=self.ref_date)
        self.assertIsNone(cleansed)
        self.assertTrue(any(e.category == "DOMAIN_VIOLATION" for e in errors))


if __name__ == "__main__":
    unittest.main()
