#!/usr/bin/env python3
"""No file in this skill may pin one machine's interpreter or home directory.

The skill is required to work across claude, codex, cursor and opencode, on any
machine. It did not. Ten occurrences across six files hardcoded either
`/opt/homebrew/bin/python3` or `/Users/fredtran/...` (pr-cost-allow-abs-path), and
three of those files were the executable adapters, so every adapter was dead on
Linux, on an Intel mac, in CI, and for any other user. That is not a style
inconsistency; it is the skill not working.

This guard fails on either literal anywhere under the skill.

Escape hatch, deliberately narrow: a line may carry the marker
`pr-cost-allow-abs-path` to declare an absolute path legitimate. That is for
locating a THIRD-PARTY binary at a well-known install prefix, which is a
different act from pinning our own interpreter. The marker must sit on the
offending line itself -- never a file-wide or pattern-wide exemption, because a
carve-out that covers a class stops being a classification and becomes a filter
that removes coverage.

The scan also fails when it finds no files to read. A checker that reports
"clean" because its own file discovery broke is worse than no checker: it is a
green light with nothing behind it.
"""

from __future__ import annotations

import pathlib
import unittest


SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]

# The two literals. `/Users/` catches any home, not just the author's, so  # pr-cost-allow-abs-path
# a different developer pinning their own path fails the same way.
BANNED = ("/opt/homebrew", "/Users/")  # pr-cost-allow-abs-path

ALLOW_MARKER = "pr-cost-allow-abs-path"

# Read every text file the skill ships. Bytecode and VCS noise carry copies of
# source strings and are not edited by hand.
SKIP_DIRS = {"__pycache__", ".git"}
SKIP_SUFFIXES = {".pyc", ".pyo"}


def scannable_files() -> list[pathlib.Path]:
    found = []
    for path in sorted(SKILL_DIR.rglob("*")):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix in SKIP_SUFFIXES:
            continue
        found.append(path)
    return found


class NoHardcodedPathsTest(unittest.TestCase):
    def test_the_scan_actually_reads_files(self) -> None:
        # An empty file list must FAIL, never pass. This is the assertion that
        # keeps the guard honest if rglob, the skip lists, or SKILL_DIR break.
        files = scannable_files()
        self.assertGreaterEqual(
            len(files),
            10,
            f"the scan found only {len(files)} files under {SKILL_DIR}; "
            "file discovery is broken, so a clean result proves nothing",
        )

    def test_no_hardcoded_interpreter_or_home_path(self) -> None:
        offenders = []
        for path in scannable_files():
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for number, line in enumerate(text.splitlines(), start=1):
                if ALLOW_MARKER in line:
                    continue
                for literal in BANNED:
                    if literal in line:
                        relative = path.relative_to(SKILL_DIR)
                        offenders.append(f"{relative}:{number}: {line.strip()}")
                        break
        self.assertEqual(
            offenders,
            [],
            "hardcoded interpreter or home paths make this skill work on one "
            "machine only:\n" + "\n".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
