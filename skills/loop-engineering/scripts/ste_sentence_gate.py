#!/usr/bin/env python3
"""Reject long prose sentences in a Markdown user-output draft."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


LINK = re.compile(r"\[([^]]+)\]\([^)]+\)")
INLINE = re.compile(r"`[^`]+`")
WORD = re.compile(r"\b[\w]+(?:[-'][\w]+)*\b")
END = re.compile(r"[.!?](?:\s+|$)")


def prose_blocks(source: str):
    fenced = False
    first = None
    lines = []

    def flush():
        nonlocal first, lines
        if lines:
            result = first, " ".join(lines)
            first, lines = None, []
            return result
        return None

    for number, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith("```"):
            block = flush()
            if block:
                yield block
            fenced = not fenced
            continue
        if fenced:
            continue
        if not line.strip() or line.lstrip().startswith("|"):
            block = flush()
            if block:
                yield block
            continue
        item = bool(re.match(r"^\s*(?:#{1,6}\s*|[-*+]\s+|\d+[.)]\s+|>\s*)", line))
        if item:
            block = flush()
            if block:
                yield block
        line = LINK.sub(r"\1", line)
        line = INLINE.sub("TERM", line)
        line = re.sub(r"https?://\S+", "TERM", line)
        line = re.sub(r"^\s*(?:#{1,6}\s*|[-*+]\s+|\d+[.)]\s+|>\s*)", "", line)
        if first is None:
            first = number
        lines.append(line.strip())
    block = flush()
    if block:
        yield block


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("draft", type=Path)
    parser.add_argument("--max-words", type=int, default=20)
    args = parser.parse_args()
    if args.max_words < 1:
        parser.error("--max-words must be positive")
    failures = []
    checked = 0
    for number, line in prose_blocks(args.draft.read_text(encoding="utf-8")):
        start = 0
        for end in END.finditer(line):
            count = len(WORD.findall(line[start:end.start()]))
            checked += 1
            if count > args.max_words:
                failures.append((number, count))
            start = end.end()
        if start < len(line):
            count = len(WORD.findall(line[start:]))
            if count:
                checked += 1
                if count > args.max_words:
                    failures.append((number, count))
    for number, count in failures:
        print(f"line {number}: {count} words; maximum {args.max_words}")
    print(f"sentence-length gate: {'fail' if failures else 'pass'}; {checked} segments checked")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
