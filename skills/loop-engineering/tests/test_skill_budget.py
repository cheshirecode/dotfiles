#!/usr/bin/env python3
"""Enforce the SKILL.md portability budget.

The 260-line ceiling existed as oral tradition: b400420 moved orchestrator mode
into references/ to get the root back under it, but nothing checked, so the next
contributor could only discover the limit by being told. One session then spent
45 of the 50 remaining lines without noticing.

A test is the right place for this rather than a note inside SKILL.md, which
would spend the budget it documents. The failure message carries the remedy.
"""

from __future__ import annotations

import pathlib
import unittest

BUDGET = 260
DESCRIPTION_BUDGET = 450  # bytes incl. newline; handover.md audits the same cap
SKILL = pathlib.Path(__file__).parents[1] / "SKILL.md"


class SkillBudgetTest(unittest.TestCase):
    def test_root_skill_stays_within_budget(self) -> None:
        lines = SKILL.read_text(encoding="utf-8").splitlines()
        self.assertLessEqual(
            len(lines),
            BUDGET,
            f"\nSKILL.md is {len(lines)} lines, over the {BUDGET}-line "
            f"portability budget by {len(lines) - BUDGET}.\n"
            "The root file is loaded on every invocation, so it stays small.\n"
            "Move a section into references/ and link it from the Route table "
            "(b400420 did this for orchestrator mode). Reference files carry no "
            "budget, so relocating is always available.",
        )

    def test_frontmatter_description_stays_within_budget(self) -> None:
        """The handover audit hard-fails on >450 bytes; enforce it between
        audits too, and find the description line instead of assuming line 3."""
        lines = SKILL.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], "---", "SKILL.md must start with frontmatter")
        frontmatter = lines[1 : lines.index("---", 1)]
        description = [l for l in frontmatter if l.startswith("description:")]
        self.assertEqual(len(description), 1, "one description line expected")
        size = len(description[0].encode("utf-8")) + 1  # + newline, as wc -c
        self.assertLessEqual(
            size,
            DESCRIPTION_BUDGET,
            f"\nfrontmatter description is {size} bytes, over the "
            f"{DESCRIPTION_BUDGET}-byte budget audited at "
            "references/handover.md. Trim the description text.",
        )
        print(f"description: {size}/{DESCRIPTION_BUDGET} bytes")

    def test_headroom_is_reported(self) -> None:
        """Not a limit — this prints remaining headroom so it is never a surprise."""
        lines = len(SKILL.read_text(encoding="utf-8").splitlines())
        print(f"SKILL.md: {lines}/{BUDGET} lines, {BUDGET - lines} remaining")


if __name__ == "__main__":
    unittest.main()
