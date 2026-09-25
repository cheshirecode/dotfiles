#!/usr/bin/env python3
"""Append a dated, sourced block of rows into a worklog program's ## Pool.

Usage: pool-append.py --file <program.md> --source <label> [--rows-file F|-]
Idempotent per (date, source): re-running with the same label is a no-op.
"""
import argparse, datetime, sys

def utc_date():
    return datetime.datetime.now(datetime.timezone.utc).date().isoformat()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--file", required=True)
    p.add_argument("--source", required=True)
    p.add_argument("--rows-file", default="-")
    p.add_argument("--date", default=None, help="ISO date; default UTC today (avoids local/UTC drift)")
    a = p.parse_args()
    text = open(a.file, encoding="utf-8").read()
    stamp = a.date or utc_date()
    marker = f"### {stamp} — {a.source}"
    if marker in text:
        print(f"already present: {marker}"); sys.exit(0)
    rows = sys.stdin.read() if a.rows_file == "-" else open(a.rows_file, encoding="utf-8").read()
    block = f"{marker}\n\n{rows.strip()}\n\n"
    lines = text.splitlines(keepends=True)
    # insert before the next '## ' heading after '## Pool'; append if absent
    idx = next((i for i, l in enumerate(lines) if l.strip() == "## Pool"), None)
    if idx is None:
        out = text.rstrip("\n") + "\n\n" + block
    else:
        end = next((i for i in range(idx + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        out = "".join(lines[:end]) + block + "".join(lines[end:])
    open(a.file, "w", encoding="utf-8").write(out)
    print(f"inserted: {marker}")

if __name__ == "__main__":
    main()
