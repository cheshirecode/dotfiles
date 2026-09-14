#!/usr/bin/env python3
"""Check every compose-table row names a skill that exists.

The compose table is the only place loop-engineering hands work to another
skill. A row whose Owner cell names a skill that was never installed, was
renamed, or was typed wrong routes the loop nowhere, and nothing says so:
the loop just records `optional-skill: skipped` and continues. That failure
is silent, which is the shape this repo keeps getting caught by.

Verifying a route by hand (`grep '$brainstorm' SKILL.md`) proves one row on
one day. This proves every row on every run, and keeps proving it when the
next row is added.

Owner names are read from column 2 only. `$council` also appears in a
`Skip when` cell, so a whole-row scan would pass on a table whose Owner
column was empty.
"""

from __future__ import annotations

import pathlib
import re
import unittest

SKILL = pathlib.Path(__file__).parents[1] / "SKILL.md"
SKILLS_ROOT = pathlib.Path(__file__).parents[2]
HEADER = "| Trigger | Owner | Handoff and replay | Skip when |"


def compose_rows() -> list[list[str]]:
    """Return the compose table's data rows as lists of cells."""
    root = SKILL.read_text(encoding="utf-8")
    assert "(references/composition.md)" in root, "composition route missing"
    lines = (SKILL.parent / "references/composition.md").read_text(encoding="utf-8").splitlines()
    start = lines.index(HEADER)
    rows = []
    for line in lines[start + 2 :]:  # skip header and its `|---|` separator
        if not line.startswith("|"):
            break
        rows.append([cell.strip() for cell in line.strip("|").split("|")])
    return rows


class ComposeRouteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rows = compose_rows()

    def test_table_is_present_and_populated(self) -> None:
        self.assertGreaterEqual(
            len(self.rows), 5, "compose table lost rows or the header moved"
        )

    def test_every_row_has_four_cells(self) -> None:
        for row in self.rows:
            self.assertEqual(
                len(row), 4, f"malformed compose row (want 4 cells): {row}"
            )

    def test_owner_cell_names_one_skill_reference(self) -> None:
        for row in self.rows:
            owner = row[1]
            self.assertRegex(
                owner,
                r"^`\$[a-z][a-z0-9-]*`$",
                f"Owner cell must be exactly one `$skill-name`, got {owner!r} "
                f"in row: {row[0]!r}",
            )

    def test_every_owner_resolves_to_a_skill_directory(self) -> None:
        for row in self.rows:
            name = row[1].strip("`$")
            self.assertTrue(
                (SKILLS_ROOT / name / "SKILL.md").is_file(),
                f"compose row {row[0]!r} routes to `${name}`, but "
                f"{SKILLS_ROOT / name / 'SKILL.md'} does not exist. Either the "
                f"skill was renamed and the row was not, or the row names a "
                f"skill that was never added.",
            )

    def test_owners_are_unique(self) -> None:
        owners = [row[1] for row in self.rows]
        duplicates = {o for o in owners if owners.count(o) > 1}
        self.assertFalse(
            duplicates, f"two compose rows claim the same owner: {duplicates}"
        )


if __name__ == "__main__":
    unittest.main()
