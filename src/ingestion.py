"""File ingestion engine for pipe-delimited flat files, CSVs, and partner JSON feeds."""

import csv
import json
import os
from typing import Any, Dict, Generator, List, Tuple


def parse_pipe_delimited_file(file_path: str) -> Generator[Dict[str, Any], None, None]:
    """
    Parses SkyPoints pipe-delimited flat files containing |H| and |D| records.
    Layout:
    |H|Member_Name|Member_Id|Enrollment_Date|Last_Flight_Date|Tier_Code|Agent_Name|State|Country|DOB|Is_Active
    |D|Elena|223457|20101012|20121013|GLD|Sam|CA|USA|03051985|A
    """
    filename = os.path.basename(file_path)
    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, raw_line in enumerate(f, start=1):
            line = raw_line.strip()
            if not line:
                continue

            parts = [p.strip() for p in line.split("|")]
            # Filter out empty leading or trailing parts caused by leading/trailing pipes
            if parts and parts[0] == "":
                parts.pop(0)
            if parts and parts[-1] == "":
                parts.pop(-1)

            if not parts:
                continue

            rec_type = parts[0].upper()
            if rec_type == "H":
                # Header record
                continue
            elif rec_type == "D":
                # Detail record
                # Position map:
                # 0: D
                # 1: Member Name
                # 2: Member ID
                # 3: Enrollment Date
                # 4: Last Flight Date
                # 5: Tier Code
                # 6: Agent Name
                # 7: State
                # 8: Country
                # 9: Post Code OR DOB (depends on whether Post Code is present)
                # 10: DOB or Is_Active
                # 11: Is_Active (if 11 elements)
                record = {
                    "_source_file": filename,
                    "_line_num": line_num,
                    "_raw_line": line,
                    "name": parts[1] if len(parts) > 1 else None,
                    "mem_id": parts[2] if len(parts) > 2 else None,
                    "enroll_dt": parts[3] if len(parts) > 3 else None,
                    "flight_dt": parts[4] if len(parts) > 4 else None,
                    "tier": parts[5] if len(parts) > 5 else None,
                    "agent_name": parts[6] if len(parts) > 6 else None,
                    "state": parts[7] if len(parts) > 7 else None,
                    "country": parts[8] if len(parts) > 8 else None,
                }

                # Handle optional Post Code or direct DOB
                if len(parts) >= 12:
                    # Includes Post Code
                    record["post_code"] = parts[9]
                    record["dob"] = parts[10]
                    record["flag"] = parts[11]
                elif len(parts) == 11:
                    # Matches sample flat file: 9 is DOB, 10 is Is_Active
                    record["post_code"] = None
                    record["dob"] = parts[9]
                    record["flag"] = parts[10]
                elif len(parts) == 10:
                    record["post_code"] = None
                    record["dob"] = parts[9]
                    record["flag"] = "A"

                yield record


def parse_csv_member_file(file_path: str) -> Generator[Dict[str, Any], None, None]:
    """
    Parses supplementary CSV member files with standard CSV formatting.
    Maps headers dynamically to standardized field names.
    """
    filename = os.path.basename(file_path)
    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for line_num, row in enumerate(reader, start=2):
            # Standardize keys to lowercase stripped
            cleaned_row = {k.strip().lower(): (v.strip() if v else "") for k, v in row.items() if k}

            # Map variations in CSV headers
            name = cleaned_row.get("name") or cleaned_row.get("member name") or cleaned_row.get("member_name")
            mem_id = cleaned_row.get("id") or cleaned_row.get("unique id") or cleaned_row.get("mem_id") or cleaned_row.get("member id")
            dob = cleaned_row.get("dob") or cleaned_row.get("date of birth")
            tier = cleaned_row.get("tiercode") or cleaned_row.get("tier type") or cleaned_row.get("tier")
            enroll_dt = cleaned_row.get("enrollmentdate") or cleaned_row.get("date of enrollment") or cleaned_row.get("enroll_dt")
            flight_dt = cleaned_row.get("flight date") or cleaned_row.get("flightdate") or cleaned_row.get("date of flight") or cleaned_row.get("flight_dt")
            country = cleaned_row.get("country", "USA")
            flag = cleaned_row.get("flag", "A")

            yield {
                "_source_file": filename,
                "_line_num": line_num,
                "_raw_line": ",".join([str(v) for v in row.values()]),
                "name": name,
                "mem_id": mem_id,
                "enroll_dt": enroll_dt,
                "flight_dt": flight_dt,
                "tier": tier,
                "agent_name": "",
                "state": "",
                "country": country,
                "post_code": None,
                "dob": dob,
                "flag": flag,
            }


def parse_json_redemption_feed(file_path: str) -> List[Dict[str, Any]]:
    """
    Parses the semi-structured JSON redemption feed and flattens it
    into a list of individual, relational transaction records.
    """
    filename = os.path.basename(file_path)
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Wrap single object in list if feed is a single JSON dictionary
    if isinstance(data, dict):
        member_feeds = [data]
    elif isinstance(data, list):
        member_feeds = data
    else:
        raise ValueError("Invalid JSON feed structure in {}".format(file_path))

    flattened_redemptions = []
    for entry in member_feeds:
        member_id = str(entry.get("member_id", "")).strip()
        feed_date = str(entry.get("feed_date", "")).strip()
        redemptions = entry.get("redemptions", [])

        for r in redemptions:
            txn_record = {
                "txn_id": str(r.get("txn_id", "")).strip(),
                "member_id": member_id,
                "feed_date": feed_date,
                "txn_date": str(r.get("txn_date", "")).strip(),
                "partner": str(r.get("partner", "")).strip(),
                "miles_redeemed": int(r.get("miles_redeemed", 0)),
                "status": str(r.get("status", "COMPLETED")).strip().upper(),
                "_source_file": filename,
            }
            flattened_redemptions.append(txn_record)

    return flattened_redemptions
