"""Date parsing and calculation utilities for SkyPoints data pipeline."""

from datetime import date, datetime
from typing import Optional, Tuple


def parse_flexible_date(val: Optional[str]) -> Tuple[Optional[date], Optional[str]]:
    """
    Parses a date string supporting multiple heterogeneous formats:
    - YYYYMMDD (e.g., '20101012')
    - YYYY-MM-DD (e.g., '2022-01-01')
    - DDMMYYYY / MMDDYYYY with leading zero (e.g., '03051985')
    - MMDDYYYY / DDMMYYYY without leading zero (e.g., '3051985', '6152022', '1052022', '12282021')
    
    Returns:
        (parsed_date, error_message): Tuple where parsed_date is datetime.date if valid,
        or None with a descriptive error string if invalid.
    """
    if val is None:
        return None, None

    cleaned = str(val).strip()
    if not cleaned or cleaned.upper() in ("NULL", "NONE", "NA", ""):
        return None, None

    # Handle standard YYYY-MM-DD format
    if "-" in cleaned:
        parts = cleaned.split("-")
        if len(parts) == 3:
            try:
                year, month, day = int(parts[0]), int(parts[1]), int(parts[2])
                if month < 1 or month > 12:
                    return None, "Invalid month: {} in date '{}' (month must be 1-12)".format(month, cleaned)
                return date(year, month, day), None
            except ValueError as e:
                return None, "Malformed calendar date '{}': {}".format(cleaned, str(e))

    # Strip any trailing decimal if string came through float conversion (e.g. '20101012.0')
    if "." in cleaned:
        cleaned = cleaned.split(".")[0].strip()

    # Digits only checks
    digits = cleaned
    if not digits.isdigit():
        return None, "Date '{}' contains non-numeric characters".format(cleaned)

    # 8-digit strings: check YYYYMMDD, DDMMYYYY, or MMDDYYYY
    if len(digits) == 8:
        # Check YYYYMMDD first if first 4 digits are reasonable year (1900-2100)
        lead_year = int(digits[:4])
        if 1900 <= lead_year <= 2100:
            month = int(digits[4:6])
            day = int(digits[6:8])
            if 1 <= month <= 12:
                try:
                    return date(lead_year, month, day), None
                except ValueError:
                    pass

        # Check DDMMYYYY or MMDDYYYY where year is trailing 4 digits
        trail_year = int(digits[4:8])
        if 1900 <= trail_year <= 2100:
            part1 = int(digits[:2])
            part2 = int(digits[2:4])
            
            # If part1 > 12, part1 must be day, part2 must be month (DDMMYYYY)
            if part1 > 12 and 1 <= part2 <= 12:
                try:
                    return date(trail_year, part2, part1), None
                except ValueError as e:
                    return None, "Invalid calendar day in '{}': {}".format(cleaned, str(e))
            # If part2 > 12, part1 must be month, part2 must be day (MMDDYYYY)
            elif part2 > 12 and 1 <= part1 <= 12:
                try:
                    return date(trail_year, part1, part2), None
                except ValueError as e:
                    return None, "Invalid calendar day in '{}': {}".format(cleaned, str(e))
            # If both <= 12, try DDMMYYYY then MMDDYYYY
            elif 1 <= part1 <= 12 and 1 <= part2 <= 12:
                try:
                    return date(trail_year, part2, part1), None
                except ValueError:
                    try:
                        return date(trail_year, part1, part2), None
                    except ValueError:
                        pass

    # 7-digit strings (e.g., '6152022' for 6/15/2022 or '1052022' for 1/05/2022 or '3051985')
    if len(digits) == 7:
        trail_year = int(digits[3:7])
        if 1900 <= trail_year <= 2100:
            # Case 1: 1-digit month, 2-digit day (e.g. 6 15 2022)
            m1 = int(digits[0])
            d1 = int(digits[1:3])
            # Case 2: 1-digit day, 2-digit month (e.g. 3 05 1985 -> day 3, month 5)
            # In '3051985': if day=3, month=05 or month=3, day=05.
            if 1 <= m1 <= 12:
                try:
                    return date(trail_year, m1, d1), None
                except ValueError:
                    pass

    return None, "Unable to parse '{}' into a valid calendar date".format(cleaned)


def compute_age(dob: Optional[date], reference_date: Optional[date] = None) -> Optional[int]:
    """
    Computes completed chronological age in full years from DOB to reference date.
    Returns None if DOB is None or if DOB is in the future.
    """
    if dob is None:
        return None

    if reference_date is None:
        reference_date = date.today()

    if dob > reference_date:
        return None

    age = reference_date.year - dob.year
    if (reference_date.month, reference_date.day) < (dob.month, dob.day):
        age -= 1
    return age


def is_stale_member(flight_date: Optional[date], reference_date: Optional[date] = None, threshold_days: int = 90) -> str:
    """
    Evaluates whether a member is considered 'Stale'.
    Rule: Stale_Member flag where days since Flight_Date > 90.
    If flight_date is None (member has never flown), marked as 'Y' (stale/inactive).
    Returns 'Y' or 'N'.
    """
    if flight_date is None:
        return "Y"

    if reference_date is None:
        reference_date = date.today()

    delta_days = (reference_date - flight_date).days
    return "Y" if delta_days > threshold_days else "N"
