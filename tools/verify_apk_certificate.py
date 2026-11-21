#!/usr/bin/env python3
"""Check every certificate fingerprint after official apksigner verification.

This checks the pinned identity, not APK cryptography. The caller must first
require a successful `apksigner verify --print-certs` exit status. Android build
tools use both `Signer #1` and `V2 Signer` labels across versions.
"""

import argparse
import re
import sys


def verify(output: str, expected: str) -> str:
    expected = expected.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("Invalid expected certificate fingerprint")
    marker = "certificate SHA-256 digest:"
    fingerprints = []
    for line in output.splitlines():
        if marker not in line:
            continue
        value = line.split(marker, 1)[1].strip().lower()
        if not re.fullmatch(r"[0-9a-f]{64}", value):
            raise ValueError("Malformed certificate fingerprint")
        fingerprints.append(value)
    if not fingerprints:
        raise ValueError("No certificate SHA-256 fingerprint reported")
    if set(fingerprints) != {expected}:
        raise ValueError("Unexpected signing certificate")
    return expected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True)
    args = parser.parse_args()
    try:
        fingerprint = verify(sys.stdin.read(), args.expected)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"Permanent signing certificate verified: {fingerprint}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
