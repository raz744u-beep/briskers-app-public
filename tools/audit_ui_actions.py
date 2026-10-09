#!/usr/bin/env python3
"""Build-time source audit of interactive UI placeholders.

Static checks do not replace widget tests or on-device end-to-end tests.
They catch shortcuts that visibly promise an action but only show a TODO
message, or empty click closures. Run on every pull request and APK build.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1] / "lib" / "screens"
BANNED = [
    (re.compile(r"next workflow step to be connected", re.I), "unconnected action"),
    (re.compile(r"open customer notes to add a note for now", re.I), "placeholder note shortcut"),
    (re.compile(r"(?:onTap|onPressed)\s*:\s*\(\s*\)\s*=>\s*\{\s*\}"),
     "empty action callback"),
    (re.compile(r"(?:onTap|onPressed)\s*:\s*\(\s*\)\s*\{\s*\}"),
     "empty action callback"),
]

issues = []
files = list(ROOT.rglob("*.dart"))
for path in files:
    body = path.read_text(encoding="utf8")
    for regex, description in BANNED:
        for hit in regex.finditer(body):
            line = body.count("\n", 0, hit.start()) + 1
            issues.append(f"{path.relative_to(ROOT)}:{line}: {description}")

print(f"Audited interactive Flutter source in {len(files)} screens.")
for issue in issues:
    print("FAIL:", issue)
if issues:
    sys.exit(1)
print("PASS: No known unfinished action placeholders or empty callbacks.")
