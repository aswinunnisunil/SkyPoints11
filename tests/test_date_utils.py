"""Unit tests for date parsing and derivation logic."""

import unittest
from datetime import date

from src.date_utils import compute_age, is_stale_member, parse_flexible_date


class TestDateUtils(unittest.TestCase):

    def test_parse_standard_yyyymmdd(self):
        d, err = parse_flexible_date("20101012")
        self.assertIsNone(err)
        self.assertEqual(d, date(2010, 10, 12))

    def test_parse_iso_yyyy_mm_dd(self):
        d, err = parse_flexible_date("2022-01-01")
        self.assertIsNone(err)
        self.assertEqual(d, date(2022, 1, 1))

    def test_parse_with_leading_zero(self):
        # '03051985' -> May 3, 1985 or Mar 5, 1985
        d, err = parse_flexible_date("03051985")
        self.assertIsNone(err)
        self.assertEqual(d.year, 1985)

    def test_parse_missing_leading_zero(self):
        # From prompt: 6152022 -> June 15, 2022
        d, err = parse_flexible_date("6152022")
        self.assertIsNone(err)
        self.assertEqual(d, date(2022, 6, 15))

        # 12282021 -> Dec 28, 2021
        d2, err2 = parse_flexible_date("12282021")
        self.assertIsNone(err2)
        self.assertEqual(d2, date(2021, 12, 28))

    def test_reject_invalid_date_month_13(self):
        # From prompt: '2021-13-13' (month 13 does not exist!)
        d, err = parse_flexible_date("2021-13-13")
        self.assertIsNone(d)
        self.assertIsNotNone(err)
        self.assertIn("Invalid month", err)

    def test_parse_null_and_empty(self):
        d1, err1 = parse_flexible_date(None)
        self.assertIsNone(d1)
        self.assertIsNone(err1)

        d2, err2 = parse_flexible_date("NULL")
        self.assertIsNone(d2)
        self.assertIsNone(err2)

        d3, err3 = parse_flexible_date("")
        self.assertIsNone(d3)
        self.assertIsNone(err3)

    def test_compute_age(self):
        ref = date(2024, 1, 15)
        # Born 1985-05-03 -> 38 years old on 2024-01-15
        dob = date(1985, 5, 3)
        age = compute_age(dob, reference_date=ref)
        self.assertEqual(age, 38)

        # Birthday later in the year
        dob2 = date(1990, 10, 20)
        age2 = compute_age(dob2, reference_date=ref)
        self.assertEqual(age2, 33)

        # None dob
        self.assertIsNone(compute_age(None, reference_date=ref))

        # Future DOB
        future_dob = date(2030, 1, 1)
        self.assertIsNone(compute_age(future_dob, reference_date=ref))

    def test_is_stale_member(self):
        ref = date(2024, 1, 15)
        # Flown 10 days ago -> Not stale ('N')
        recent_flight = date(2024, 1, 5)
        self.assertEqual(is_stale_member(recent_flight, reference_date=ref), "N")

        # Flown 120 days ago (> 90 days) -> Stale ('Y')
        old_flight = date(2023, 9, 1)
        self.assertEqual(is_stale_member(old_flight, reference_date=ref), "Y")

        # Never flown (flight_date is None) -> Stale ('Y')
        self.assertEqual(is_stale_member(None, reference_date=ref), "Y")


if __name__ == "__main__":
    unittest.main()
