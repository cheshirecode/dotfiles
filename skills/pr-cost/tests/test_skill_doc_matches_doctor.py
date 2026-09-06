#!/usr/bin/env python3
"""SKILL.md's status table must match the statuses the doctor can emit.

The six-status table in SKILL.md is a second copy of what
`scripts/pr_cost_doctor.py` actually does, and the doctor's own module
docstring is a third. Copies drift, and this particular drift is expensive:
the table tells a reader which statuses fail a run, so a stale exit column
means someone reads `no-signal` as harmless, or adds a failing status that
nobody learns to watch for.

The code is the authority here, not either prose copy. These tests read the
statuses out of the doctor's assignment sites and its own failing-status
tuple, then require the documentation to agree.

Two anchoring notes, because a looser pattern would pass while wrong:

  - Status names are matched as whole tokens. `ok` is a substring of `hook`,
    and the doctor's docstring contains "a hook adapter exists", so a
    substring check for `ok` passes against a docstring that never mentions
    the status.
  - The table is read only from inside the `## Self-diagnosis` section. A
    row-shaped line elsewhere in SKILL.md must not be able to satisfy an
    assertion about this table.

The extraction is itself asserted non-empty. A parser that quietly matches
nothing turns every comparison below into `set() == set()`, which passes.
"""

from __future__ import annotations

import pathlib
import re
import unittest


SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
SKILL_MD = SKILL_DIR / "SKILL.md"
DOCTOR = SKILL_DIR / "scripts" / "pr_cost_doctor.py"

# `"status": "<name>"` in a returned dict, and `entry["status"] = "<name>"`.
# Both require the key, so prose in the docstring cannot match.
STATUS_ASSIGNMENT = re.compile(r'"status"\]?\s*[:=]\s*"([a-z-]+)"')

# The tuple the report's `failed` list is computed from.
FAILING_TUPLE = re.compile(r'lane\["status"\]\s+in\s+\(([^)]*)\)')

TABLE_ROW = re.compile(r"^\|\s*`([a-z-]+)`\s*\|(.*)\|\s*(\S+)\s*\|\s*$")

# One line of the doctor docstring's status block: two spaces, the status,
# then its description column. Matched as a BLOCK ROW rather than as a
# mention anywhere in the docstring -- see the test for why that matters.
DOCSTRING_STATUS_ROW = re.compile(r"^  ([a-z][a-z-]*)\s+\S", re.MULTILINE)


def doctor_source() -> str:
    return DOCTOR.read_text(encoding="utf-8")


def doctor_docstring() -> str:
    return doctor_source().split('"""')[1]


def statuses_the_doctor_emits() -> set[str]:
    return set(STATUS_ASSIGNMENT.findall(doctor_source()))


def statuses_the_doctor_fails_on() -> set[str]:
    match = FAILING_TUPLE.search(doctor_source())
    if match is None:
        return set()
    return set(re.findall(r'"([a-z-]+)"', match.group(1)))


def self_diagnosis_section() -> str:
    text = SKILL_MD.read_text(encoding="utf-8")
    start = text.find("## Self-diagnosis")
    if start == -1:
        return ""
    end = text.find("\n## ", start + 1)
    return text[start:] if end == -1 else text[start:end]


def documented_rows() -> dict[str, str]:
    """Map documented status -> its exit-code cell, from that section only."""
    rows = {}
    for line in self_diagnosis_section().splitlines():
        match = TABLE_ROW.match(line)
        if match:
            rows[match.group(1)] = match.group(3).strip()
    return rows


class SkillDocMatchesDoctorTest(unittest.TestCase):
    def test_both_extractions_find_something(self) -> None:
        # The guard on the rest of this file. Every assertion below compares
        # two extracted sets, and two empty sets are equal, so a broken
        # pattern would read as agreement.
        # The threshold is "found anything at all", deliberately not a row
        # count. A first version required 6 of each, and then deleting one
        # legitimate table row tripped this test too -- reporting a broken
        # parser when the parser was fine and the table was wrong. Counting
        # content here would duplicate the equality tests and misdiagnose
        # their failures.
        emitted = statuses_the_doctor_emits()
        rows = documented_rows()
        self.assertNotEqual(
            emitted,
            set(),
            f"no status assignments matched in {DOCTOR.name}; the extraction "
            "is broken, so agreement below proves nothing",
        )
        self.assertNotEqual(
            rows,
            {},
            "no table rows matched in SKILL.md's Self-diagnosis section; the "
            "extraction is broken, so agreement proves nothing",
        )
        self.assertNotEqual(
            statuses_the_doctor_fails_on(),
            set(),
            "could not read the doctor's failing-status tuple",
        )
        self.assertNotEqual(
            set(DOCSTRING_STATUS_ROW.findall(doctor_docstring())),
            set(),
            "no rows matched in the doctor docstring's status block; the "
            "extraction is broken, so agreement proves nothing",
        )

    def test_the_table_lists_exactly_the_statuses_the_doctor_emits(self) -> None:
        emitted = statuses_the_doctor_emits()
        documented = set(documented_rows())
        self.assertEqual(
            documented,
            emitted,
            "SKILL.md's status table and the doctor disagree.\n"
            f"  documented but never emitted: {sorted(documented - emitted)}\n"
            f"  emitted but undocumented:     {sorted(emitted - documented)}",
        )

    def test_the_exit_column_marks_exactly_the_failing_statuses(self) -> None:
        rows = documented_rows()
        # The table writes a failing exit as bold **1**; anything else is a
        # pass. Compare the marked set to the tuple `failed` is computed from.
        documented_failing = {
            status for status, exit_cell in rows.items() if "1" in exit_cell
        }
        self.assertEqual(
            documented_failing,
            statuses_the_doctor_fails_on(),
            "SKILL.md's exit column does not match the statuses the doctor "
            "actually fails on. A reader would learn the wrong set.",
        )

    def test_the_doctors_docstring_block_lists_the_same_statuses(self) -> None:
        # The third copy of the list. This compares the docstring's status
        # BLOCK, not whether each name appears somewhere in the docstring.
        #
        # The looser version was written first and could not be proved red.
        # Deleting the `ok` row left the test green, because the docstring
        # says "`unavailable` must never read as `ok`" further down, so the
        # token survived the row's removal. A presence check can only catch
        # losing a name that happens to occur exactly once -- it certifies
        # the rows it cannot see.
        rows = set(DOCSTRING_STATUS_ROW.findall(doctor_docstring()))
        self.assertEqual(
            rows,
            set(documented_rows()),
            "the doctor's docstring status block and SKILL.md's table "
            "disagree. If the block was only reformatted, this pattern reads "
            "two-space indent then the status then its description column.",
        )


if __name__ == "__main__":
    unittest.main()
