"""Static, offline preflight for a PRIVATE schema-only Briskers sandbox baseline.

This is not a database migration runner, permission installer, RLS proof, or a
replacement for hosted tests. It never connects to a database.
"""
import argparse
from pathlib import Path
import re
import sys

# The earliest historical migration references appointment_requests before
# creating Briskers tables. A fresh Supabase branch without the underlying
# schema fails before it can become a usable isolated test.
REQUIRED_BEFORE_REPLAY = (
    "appointment_requests",
    "businesses",
    "customers",
    "jobs",
    "job_visits",
    "sales_documents",
    "financial_transactions",
    "document_number_reuse",
)
SENSITIVE_TABLES = (
    "businesses", "customers", "vehicles", "jobs", "sales_documents",
    "financial_transactions", "payments", "memberships", "customer_private",
)


def check_baseline(sql: str) -> list[str]:
    # Strip comments for matching object declarations. Do not attempt to
    # execute or sanitize arbitrary SQL. Private review is still mandatory.
    text = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    text = re.sub(r"(?m)^\s*--[^\n]*", "", text)
    errors = []
    if not re.search(
        r'\bCREATE\s+SCHEMA\s+(?:IF\s+NOT\s+EXISTS\s+)?["\']?briskers["\']?\b',
        text, re.I,
    ):
        errors.append("Missing CREATE SCHEMA briskers; first historical migration cannot run.")

    for name in REQUIRED_BEFORE_REPLAY:
        pattern = (
            r'\bCREATE\s+(?:UNLOGGED\s+)?TABLE\s+'
            r'(?:IF\s+NOT\s+EXISTS\s+)?["\']?briskers["\']?\s*\.\s*'
            + re.escape(name) + r'\b'
        )
        if not re.search(pattern, text, re.I):
            errors.append(f"Missing initial core table briskers.{name}.")

    # Obvious top-level user-data statements disqualify a file that claims
    # to be a schema-only baseline. This is a conservative *screen*, not a
    # complete SQL parser. A function body may legitimately contain DML.
    if re.search(r'(?mi)^\s*COPY\s+(?:(?:["\']?briskers["\']?)\.)?', text):
        errors.append("COPY data statements are forbidden in an empty-schema baseline.")
    for table in SENSITIVE_TABLES:
        pattern = (
            r'(?mi)^\s*INSERT\s+INTO\s+(?:(?:["\']?briskers["\']?)\.)?'
            + re.escape(table) + r'\b'
        )
        if re.search(pattern, text):
            errors.append(f"Data INSERT targeting {table} needs separate fixture review.")
    if re.search(r'(?mi)^\s*\\(?:connect|copy|i(?:nclude)?)\b', text):
        errors.append("psql external inclusion, connection and copy commands are forbidden.")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path, help="Private schema-only baseline SQL to screen")
    args = parser.parse_args()
    try:
        sql = args.baseline.read_text(encoding="utf-8")
    except OSError as error:
        print(f"BLOCK: baseline unreadable: {error}", file=sys.stderr)
        return 2
    errors = check_baseline(sql)
    if errors:
        for error in errors:
            print(f"BLOCK: {error}", file=sys.stderr)
        return 1
    print(
        "PASS: basic schema prerequisites found and no obvious business-data "
        "copy detected. This does NOT authorize branch creation, migration "
        "execution, permission changes or live deletion."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
