"""Configuration constants and schema definitions for SkyPoints Loyalty Data Pipeline."""

import os
from datetime import date

# Base directory
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Data directories
DATA_DIR = os.path.join(BASE_DIR, "data")
RAW_DATA_DIR = os.path.join(DATA_DIR, "raw")
OUTPUT_DATA_DIR = os.path.join(DATA_DIR, "output")
DB_PATH = os.path.join(OUTPUT_DATA_DIR, "skypoints_loyalty.db")

# Business thresholds
STALE_MEMBER_THRESHOLD_DAYS = 90
REFERENCE_DATE = date.today()

# Supported country codes and target table mappings
COUNTRY_TABLE_MAPPING = {
    "IND": "table_india",
    "INDIA": "table_india",
    "USA": "table_usa",
    "US": "table_usa",
    "CAN": "table_canada",
    "CANADA": "table_canada",
    "PHIL": "table_philippines",
    "PHL": "table_philippines",
    "PH": "table_philippines",
    "AU": "table_australia",
    "AUS": "table_australia",
    "AUSTRALIA": "table_australia",
}

DEFAULT_COUNTRY_TABLE = "table_other_countries"

# Valid domain values
VALID_TIERS = {"SLV", "GLD", "PLT", "SILVER", "GOLD", "PLATINUM"}
VALID_FLAGS = {"A", "I", "Y", "N", "ACTIVE", "INACTIVE"}
VALID_REDEMPTION_STATUSES = {"COMPLETED", "PENDING", "CANCELLED", "REVERSED"}

# Mandatory fields as specified in data dictionary
MANDATORY_FIELDS = ["name", "mem_id", "enroll_dt"]
