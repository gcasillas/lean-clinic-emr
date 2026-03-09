#!/usr/bin/env python3
"""Seed synthetic patient records into OpenEMR's patient_data table for sandbox use."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path


def parse_env_file(env_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def sql_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "''")


def sql_literal(value: str | int | None, *, raw: bool = False) -> str:
    if value is None:
        return "NULL"
    if raw:
        return str(value)
    if isinstance(value, int):
        return str(value)
    return f"'{sql_escape(value)}'"


def generate_insert_sql(patients: list[dict], clear_existing: bool) -> str:
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S")

    sql_lines = [
        "START TRANSACTION;",
    ]

    if clear_existing:
        sql_lines.append("DELETE FROM patient_data WHERE pubpid LIKE 'LC-%';")

    sql_lines.extend(
        [
            "SET @next_pid := (SELECT COALESCE(MAX(pid), 0) + 1 FROM patient_data);",
            "SET @next_pubnum := (SELECT COALESCE(MAX(CAST(SUBSTRING(pubpid, 4) AS UNSIGNED)), 0) + 1 FROM patient_data WHERE pubpid REGEXP '^LC-[0-9]+$');",
        ]
    )

    for patient in patients:
        first_name = patient["name"]["first"]
        last_name = patient["name"]["last"]
        birth_date = patient["birth_date"]
        sex = patient["sex"]
        phone = patient["phone"]

        row_data = [
            ("uuid", "NULL"),
            ("title", sql_literal("")),
            ("language", sql_literal("en")),
            ("financial", sql_literal("")),
            ("fname", sql_literal(first_name)),
            ("lname", sql_literal(last_name)),
            ("mname", sql_literal("")),
            ("DOB", sql_literal(birth_date)),
            ("street", sql_literal("")),
            ("postal_code", sql_literal("")),
            ("city", sql_literal("")),
            ("state", sql_literal("")),
            ("country_code", sql_literal("US")),
            ("drivers_license", sql_literal("")),
            ("ss", sql_literal("")),
            ("occupation", "NULL"),
            ("phone_home", sql_literal(phone)),
            ("phone_biz", sql_literal("")),
            ("phone_contact", sql_literal(phone)),
            ("phone_cell", sql_literal(phone)),
            ("pharmacy_id", sql_literal(0)),
            ("status", sql_literal("")),
            ("contact_relationship", sql_literal("")),
            ("date", sql_literal(now)),
            ("sex", sql_literal(sex)),
            ("referrer", sql_literal("")),
            ("referrerID", sql_literal("")),
            ("providerID", "NULL"),
            ("ref_providerID", "NULL"),
            ("email", sql_literal("")),
            ("email_direct", sql_literal("")),
            ("ethnoracial", sql_literal("")),
            ("race", sql_literal("")),
            ("ethnicity", sql_literal("")),
            ("religion", sql_literal("")),
            ("interpretter", sql_literal("")),
            ("interpreter_needed", "NULL"),
            ("migrantseasonal", sql_literal("")),
            ("family_size", sql_literal("")),
            ("monthly_income", sql_literal("")),
            ("billing_note", "NULL"),
            ("homeless", sql_literal("")),
            ("financial_review", "NULL"),
            ("pubpid", "CONCAT('LC-', LPAD(@next_pubnum, 4, '0'))"),
            ("pid", "@next_pid"),
            ("genericname1", sql_literal("")),
            ("genericval1", sql_literal("")),
            ("genericname2", sql_literal("")),
            ("genericval2", sql_literal("")),
            ("hipaa_mail", sql_literal("NO")),
            ("hipaa_voice", sql_literal("NO")),
            ("hipaa_notice", sql_literal("NO")),
            ("hipaa_message", sql_literal("")),
            ("hipaa_allowsms", sql_literal("NO")),
            ("hipaa_allowemail", sql_literal("NO")),
            ("squad", sql_literal("")),
            ("fitness", sql_literal(0)),
            ("referral_source", sql_literal("")),
            ("usertext1", sql_literal("")),
            ("usertext2", sql_literal("")),
            ("usertext3", sql_literal("")),
            ("usertext4", sql_literal("")),
            ("usertext5", sql_literal("")),
            ("usertext6", sql_literal("")),
            ("usertext7", sql_literal("")),
            ("usertext8", sql_literal("")),
            ("userlist1", sql_literal("")),
            ("userlist2", sql_literal("")),
            ("userlist3", sql_literal("")),
            ("userlist4", sql_literal("")),
            ("userlist5", sql_literal("")),
            ("userlist6", sql_literal("")),
            ("userlist7", sql_literal("")),
            ("pricelevel", sql_literal("standard")),
            ("regdate", sql_literal(now)),
            ("completed_ad", sql_literal("NO")),
            ("vfc", sql_literal("")),
            ("mothersname", sql_literal("")),
            ("allow_imm_reg_use", sql_literal("")),
            ("allow_imm_info_share", sql_literal("")),
            ("allow_health_info_ex", sql_literal("")),
            ("allow_patient_portal", sql_literal("YES")),
            ("deceased_reason", sql_literal("")),
            ("cmsportal_login", sql_literal("")),
            ("county", sql_literal("")),
            ("dupscore", sql_literal(-9)),
        ]

        columns = [column for column, _ in row_data]
        values = [value for _, value in row_data]
        if len(columns) != len(values):
            raise RuntimeError("patient_data insert columns and values are out of sync")

        insert_sql = (
            f"INSERT INTO patient_data ({', '.join(columns)}) VALUES ({', '.join(values)});"
        )
        sql_lines.append(insert_sql)
        sql_lines.append("SET @next_pid := @next_pid + 1;")
        sql_lines.append("SET @next_pubnum := @next_pubnum + 1;")

    sql_lines.append("COMMIT;")
    return "\n".join(sql_lines) + "\n"


def run_sql(container: str, user: str, password: str, database: str, sql: str) -> None:
    cmd = [
        "docker",
        "exec",
        "-i",
        container,
        "mariadb",
        f"-u{user}",
        f"-p{password}",
        database,
    ]
    subprocess.run(cmd, input=sql, text=True, check=True)


def count_seeded(container: str, user: str, password: str, database: str) -> int:
    cmd = [
        "docker",
        "exec",
        container,
        "mariadb",
        f"-u{user}",
        f"-p{password}",
        database,
        "-Nse",
        "SELECT COUNT(*) FROM patient_data WHERE pubpid LIKE 'LC-%';",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return int(result.stdout.strip() or "0")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        default="phase1-sandbox/data/mock_clinic_data.json",
        help="Path to generated mock clinic JSON",
    )
    parser.add_argument(
        "--env-file",
        default="phase1-sandbox/.env",
        help="Path to env file with MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE",
    )
    parser.add_argument(
        "--db-container",
        default="openemr-db",
        help="Docker container name for database",
    )
    parser.add_argument(
        "--clear-existing",
        action="store_true",
        help="Delete previously seeded LC-* records before inserting",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    env_path = Path(args.env_file)

    if not input_path.exists():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)
    if not env_path.exists():
        print(f"Env file not found: {env_path}", file=sys.stderr)
        sys.exit(1)

    env_values = parse_env_file(env_path)
    mysql_user = env_values.get("MYSQL_USER")
    mysql_password = env_values.get("MYSQL_PASSWORD")
    mysql_database = env_values.get("MYSQL_DATABASE")

    if not mysql_user or not mysql_password or not mysql_database:
        print(".env must include MYSQL_USER, MYSQL_PASSWORD, and MYSQL_DATABASE", file=sys.stderr)
        sys.exit(1)

    dataset = json.loads(input_path.read_text(encoding="utf-8"))
    patients = dataset.get("patients", [])
    if not patients:
        print("No patients found in input JSON", file=sys.stderr)
        sys.exit(1)

    sql = generate_insert_sql(patients, args.clear_existing)

    try:
        run_sql(args.db_container, mysql_user, mysql_password, mysql_database, sql)
        seeded = count_seeded(args.db_container, mysql_user, mysql_password, mysql_database)
    except subprocess.CalledProcessError as exc:
        print(f"Database seed failed: {exc}", file=sys.stderr)
        sys.exit(1)

    print(f"Inserted {len(patients)} records. Current LC-* records in OpenEMR: {seeded}")


if __name__ == "__main__":
    main()
