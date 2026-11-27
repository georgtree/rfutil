"""Reject empty or failed test runs, including accidentally skipped vector coverage."""
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8-sig")
summary = re.findall(r"^all\.tcl:\s+Total\s+(\d+)\s+Passed\s+(\d+)\s+Skipped\s+(\d+)\s+Failed\s+(\d+)\s*$", text, re.M)
if len(summary) != 1:
    raise SystemExit("Expected one Tcltest summary")
total, passed, skipped, failed = map(int, summary[0])
if not total or not passed or skipped or failed:
    raise SystemExit(f"Incomplete test run: {total=}, {passed=}, {skipped=}, {failed=}")
if re.search(r"(?:^|\n)(?:Test file error:|.* FAILED)", text):
    raise SystemExit("Test errors were reported")
print(f"Verified {passed} passing tests, none skipped")
