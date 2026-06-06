#!/usr/bin/env python3
"""Mechanical `/stacking-strategy` markdown → tasks-JSON parser.

The `/stacking-strategy` skill (cheshirecode/<repo> repo) emits a `### Stack Plan` section
followed by `#### PR N: <title>` blocks. Each PR section may contain a
`Depends on:` line listing prior PR numbers / slugs.

This script converts that markdown into the JSON shape that
`bin/project.sh new` accepts on stdin:

  [{"slug": "<derived>", "title": "<PR title>",
    "depends_on": ["<prior-slug>", ...]}]

Usage:
  bin/_stacking_strategy_parser.py < plan.md
  cat plan.md | bin/_stacking_strategy_parser.py --prefix=engx-

`--prefix=` is prepended to each derived slug; default empty. Slug derivation:
  - title → lowercase
  - non-alphanumeric → hyphen
  - collapse repeats, strip leading/trailing hyphens
  - truncate to 30 chars at the last hyphen boundary
"""

from __future__ import annotations

import argparse
import json
import re
import sys


HEADING_RE = re.compile(r"^####\s+PR\s+(\d+)\s*:\s*(.+?)\s*$")
DEPENDS_RE = re.compile(r"^\s*[*-]?\s*\*?\*?Depends on:?\*?\*?\s*(.+?)\s*$", re.IGNORECASE)
STACK_PLAN_RE = re.compile(r"^###\s+Stack Plan\s*$", re.IGNORECASE)


def slugify(title: str, prefix: str = "", maxlen: int = 30) -> str:
  s = title.lower()
  s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
  if prefix:
    s = prefix + s
  if len(s) > maxlen:
    cut = s[:maxlen]
    # Trim at last hyphen so we don't end mid-word.
    if "-" in cut:
      cut = cut[: cut.rfind("-")]
    s = cut
  return s


def parse(text: str, prefix: str = "") -> list[dict]:
  lines = text.splitlines()
  in_stack = False
  current: dict | None = None
  pr_by_number: dict[str, dict] = {}
  out: list[dict] = []

  for line in lines:
    if STACK_PLAN_RE.match(line):
      in_stack = True
      continue
    if not in_stack:
      continue
    # Bail when a new top-level `### ` (not `#### `) section starts.
    if line.startswith("### ") and not line.startswith("#### "):
      break
    m = HEADING_RE.match(line)
    if m:
      if current is not None:
        out.append(current)
      pr_num = m.group(1)
      title = m.group(2)
      slug = slugify(title, prefix=prefix)
      current = {"slug": slug, "title": title, "depends_on": []}
      pr_by_number[pr_num] = current
      continue
    if current is None:
      continue
    dm = DEPENDS_RE.match(line)
    if dm:
      raw = dm.group(1).strip()
      if raw.lower() in ("none", "n/a", "-", ""):
        continue
      # Split on comma + "and" + whitespace.
      parts = re.split(r"\s*(?:,|\band\b|&)\s*", raw)
      for p in parts:
        p = p.strip().strip(".").strip(")").strip("(")
        if not p:
          continue
        # Could be "PR 1" / "#1" / a literal slug — try to resolve to known PR
        # numbers first.
        pn = re.match(r"^(?:PR\s*)?#?(\d+)$", p, re.IGNORECASE)
        if pn:
          ref = pr_by_number.get(pn.group(1))
          if ref:
            current["depends_on"].append(ref["slug"])
            continue
          # Forward reference; carry the literal for now and resolve at the end.
          current["depends_on"].append(f"__pr_{pn.group(1)}__")
          continue
        # Otherwise assume it's already a slug.
        current["depends_on"].append(slugify(p, prefix=prefix) if " " in p else p)

  if current is not None:
    out.append(current)

  # Resolve forward `__pr_N__` placeholders.
  for entry in out:
    resolved: list[str] = []
    for d in entry["depends_on"]:
      m = re.match(r"^__pr_(\d+)__$", d)
      if m and m.group(1) in pr_by_number:
        resolved.append(pr_by_number[m.group(1)]["slug"])
      else:
        resolved.append(d)
    entry["depends_on"] = resolved

  # Drop empty depends_on arrays for cleaner JSON.
  for entry in out:
    if not entry["depends_on"]:
      del entry["depends_on"]
  return out


def main() -> None:
  ap = argparse.ArgumentParser()
  ap.add_argument("--prefix", default="")
  ap.add_argument("--indent", type=int, default=None)
  args = ap.parse_args()
  text = sys.stdin.read()
  tasks = parse(text, prefix=args.prefix)
  if not tasks:
    print("_stacking_strategy_parser: no '### Stack Plan' / '#### PR N:' blocks found", file=sys.stderr)
    sys.exit(1)
  print(json.dumps(tasks, indent=args.indent))


if __name__ == "__main__":
  main()
