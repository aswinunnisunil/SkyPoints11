"""Data validation engine and Data Quality (DQ) framework for SkyPoints Loyalty."""

from datetime import date
from typing import Any, Dict, List, Optional, Tuple

from src.config import MANDATORY_FIELDS, VALID_FLAGS, VALID_TIERS
from src.date_utils import compute_age, parse_flexible_date


class ValidationError:
    """Represents a data validation failure for routing to the Dead Letter Queue."""
    def __init__(self, category: str, field: str, message: str):
        self.category = category
        self.field = field
        self.message = message

    def to_dict(self) -> Dict[str, str]:
        return {
            "error_category": self.category,
            "error_field": self.field,
            "error_message": self.message,
        }


def validate_member_record(
    raw_record: Dict[str, Any], 
    reference_date: Optional[date] = None
) -> Tuple[Optional[Dict[str, Any]], List[ValidationError]]:
    """
    Validates a raw member dictionary against business rules and data quality standards.
    Catches mandatory field nulls, invalid dates (e.g. month 13 like '2021-13-13'),
    chronological inversions, and domain violations.
    
    Returns:
        (validated_dict, errors): Tuple of cleansed dictionary (if valid) and list of ValidationErrors.
    """
    if reference_date is None:
        reference_date = date.today()

    errors = []
    cleansed = {}

    # 1. Mandatory Field Checks: Name
    name = raw_record.get("name")
    if not name or str(name).strip().upper() in ("", "NULL", "NONE"):
        errors.append(ValidationError("MANDATORY_NULL", "name", "Mandatory field 'name' is missing or NULL"))
    else:
        cleansed["name"] = str(name).strip()

    # 2. Mandatory Field Checks: Member ID
    mem_id = raw_record.get("mem_id")
    if not mem_id or str(mem_id).strip().upper() in ("", "NULL", "NONE"):
        errors.append(ValidationError("MANDATORY_NULL", "mem_id", "Mandatory field 'mem_id' is missing or NULL"))
    else:
        cleansed["mem_id"] = str(mem_id).strip()

    # 3. Mandatory Field Checks: Enrollment Date
    raw_enroll = raw_record.get("enroll_dt")
    if not raw_enroll or str(raw_enroll).strip().upper() in ("", "NULL", "NONE"):
        errors.append(ValidationError("MANDATORY_NULL", "enroll_dt", "Mandatory field 'enroll_dt' is missing or NULL"))
        enroll_dt = None
    else:
        enroll_dt, enroll_err = parse_flexible_date(raw_enroll)
        if enroll_err:
            errors.append(ValidationError("INVALID_DATE", "enroll_dt", enroll_err))
        elif enroll_dt > reference_date:
            errors.append(ValidationError("CHRONOLOGY_ERROR", "enroll_dt", 
                                          "Enrollment date {} cannot be in the future".format(enroll_dt)))
        cleansed["enroll_dt"] = enroll_dt

    # 4. Flight Date Validation (Optional)
    raw_flight = raw_record.get("flight_dt")
    flight_dt = None
    if raw_flight and str(raw_flight).strip().upper() not in ("", "NULL", "NONE"):
        flight_dt, flight_err = parse_flexible_date(raw_flight)
        if flight_err:
            errors.append(ValidationError("INVALID_DATE", "flight_dt", flight_err))
        elif flight_dt > reference_date:
            errors.append(ValidationError("CHRONOLOGY_ERROR", "flight_dt", 
                                          "Flight date {} cannot be in the future".format(flight_dt)))
        elif enroll_dt and flight_dt < enroll_dt:
            errors.append(ValidationError("CHRONOLOGY_ERROR", "flight_dt", 
                                          "Flight date {} is earlier than enrollment date {}".format(flight_dt, enroll_dt)))
    cleansed["flight_dt"] = flight_dt

    # 5. Date of Birth Validation (Optional)
    raw_dob = raw_record.get("dob")
    dob = None
    if raw_dob and str(raw_dob).strip().upper() not in ("", "NULL", "NONE"):
        dob, dob_err = parse_flexible_date(raw_dob)
        if dob_err:
            errors.append(ValidationError("INVALID_DATE", "dob", dob_err))
        elif dob > reference_date:
            errors.append(ValidationError("CHRONOLOGY_ERROR", "dob", 
                                          "Date of birth {} is in the future".format(dob)))
        elif enroll_dt and dob > enroll_dt:
            errors.append(ValidationError("CHRONOLOGY_ERROR", "dob", 
                                          "Date of birth {} is after enrollment date {}".format(dob, enroll_dt)))
    cleansed["dob"] = dob

    # 6. Domain Validation: Active Flag
    raw_flag = raw_record.get("flag", "A")
    flag_str = str(raw_flag).strip().upper() if raw_flag is not None else "A"
    if flag_str in ("Y", "1", "TRUE"):
        flag_str = "A"
    elif flag_str in ("N", "0", "FALSE"):
        flag_str = "I"
    elif flag_str not in ("A", "I"):
        errors.append(ValidationError("DOMAIN_VIOLATION", "flag", 
                                      "Active member flag '{}' is invalid. Expected 'A' or 'I'".format(flag_str)))
    cleansed["flag"] = flag_str

    # 7. Tier Code (Length and format check)
    raw_tier = raw_record.get("tier", "SLV")
    tier_str = str(raw_tier).strip().upper() if raw_tier is not None else "SLV"
    if len(tier_str) > 10:
        errors.append(ValidationError("DOMAIN_VIOLATION", "tier", "Tier code exceeds maximum allowed length"))
    cleansed["tier"] = tier_str

    # 8. Country and State
    raw_country = raw_record.get("country", "")
    country_str = str(raw_country).strip().upper() if raw_country is not None else ""
    cleansed["country"] = country_str

    raw_state = raw_record.get("state", "")
    cleansed["state"] = str(raw_state).strip().upper() if raw_state is not None else ""

    raw_agent = raw_record.get("agent_name", "")
    cleansed["agent_name"] = str(raw_agent).strip() if raw_agent is not None else ""

    raw_post = raw_record.get("post_code")
    try:
        cleansed["post_code"] = int(raw_post) if raw_post not in (None, "", "NULL") else None
    except (ValueError, TypeError):
        cleansed["post_code"] = None

    if errors:
        return None, errors

    return cleansed, []
