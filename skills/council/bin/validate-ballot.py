#!/usr/bin/env python3
"""Validate one Council Stage 5 ballot before tallying it."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


CRITERIA = {
  "TRACES",
  "SOLVES-EXTANT-PAIN",
  "N-THRESHOLD-MET",
  "COST-PROPORTIONATE",
  "NON-INFRA-PADDING",
}


def fail(message: str) -> None:
  print(f"validate-ballot: {message}", file=sys.stderr)
  raise SystemExit(1)


def parse_ids(value: str) -> set[int]:
  if not value:
    return set()
  try:
    return {int(item) for item in value.split(",")}
  except ValueError:
    fail("--unresolved must be a comma-separated list of item numbers")
  raise AssertionError("unreachable")


def validate_reject(item: int, value: str) -> None:
  parts = [part.strip() for part in value.removeprefix("REJECT:").split(",")]
  criterion_count = 0
  for part in parts:
    if part not in CRITERIA:
      break
    criterion_count += 1
  if criterion_count == 0 or criterion_count == len(parts):
    fail(f"item {item} REJECT must name a valid criterion and give a reason")


def main() -> None:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--items", type=int, required=True, help="number of collated items")
  parser.add_argument("--unresolved", default="", help="comma-separated UNRESOLVED MATERIAL items")
  parser.add_argument("ballot", type=pathlib.Path)
  args = parser.parse_args()

  if args.items < 1:
    fail("--items must be positive")
  unresolved = parse_ids(args.unresolved)
  expected = set(range(1, args.items + 1))
  if not unresolved <= expected:
    fail("--unresolved contains an item outside --items")

  seen: dict[int, str] = {}
  for line_number, line in enumerate(args.ballot.read_text().splitlines(), start=1):
    stripped = line.strip()
    if not stripped or stripped == "## Stage 5 ballots" or re.fullmatch(r"Voter \d+:", stripped):
      continue
    match = re.fullmatch(r"item (\d+): (APPROVE|QUALIFY: .+|REJECT: .+)", stripped)
    if not match:
      fail(f"line {line_number} is not a structured item ballot")
    item = int(match.group(1))
    vote = match.group(2)
    if item not in expected:
      fail(f"item {item} is outside the collated item range")
    if item in seen:
      fail(f"item {item} appears more than once")
    if vote == "APPROVE" and item in unresolved:
      fail(f"item {item} APPROVE conflicts with UNRESOLVED MATERIAL")
    if vote.startswith("REJECT:"):
      validate_reject(item, vote)
    seen[item] = vote

  missing = sorted(expected - seen.keys())
  if missing:
    fail(f"missing item ballots: {','.join(map(str, missing))}")


if __name__ == "__main__":
  main()
