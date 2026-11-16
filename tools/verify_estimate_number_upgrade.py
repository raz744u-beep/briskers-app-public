#!/usr/bin/env python3
"""Insert and inspect synthetic estimate fixtures on the offline test emulator."""
import argparse
import json
import sqlite3

BUSINESS = "estimate-upgrade-synthetic"
DRAFT = "local-estimate-00000000-0000-4000-8000-000000000003"
SENT = "00000000-0000-4000-8000-000000000004"
NUMBER = "E-1999"
MALFORMED = "00000000-0000-4000-8000-000000000005"


def seed(db):
    db.executemany(
        """INSERT INTO local_documents
           (id,business_id,customer_id,kind,document_number,status,total,document_date,sync_state)
           VALUES(?,?,?,'estimate',?,?,?,'2026-11-16',?)""",
        [
            (DRAFT, BUSINESS, "fixture-customer", None, "draft", 1879.03, "pending"),
            (MALFORMED, BUSINESS, "fixture-customer", "EST-1234567890ABCDEF", "draft", 137.19, "synced"),
            (SENT, BUSINESS, "fixture-customer", "E-1997", "sent", 90, "synced"),
        ],
    )


def verify(db):
    rows = db.execute(
        """SELECT id,document_number,status,total FROM local_documents
           WHERE business_id=? ORDER BY id DESC""",
        (BUSINESS,),
    ).fetchall()
    assert rows == [
        (DRAFT, NUMBER, "draft", 1879.03),
        (MALFORMED, "E-1998", "draft", 137.19),
        (SENT, "E-1997", "sent", 90),
    ], rows
    print(json.dumps({"new_number": NUMBER, "historical_number": rows[2][1], "rows": len(rows)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["seed", "verify"])
    parser.add_argument("database")
    args = parser.parse_args()
    with sqlite3.connect(args.database) as db:
        (seed if args.action == "seed" else verify)(db)
        db.commit()
        if args.action == "seed":
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
