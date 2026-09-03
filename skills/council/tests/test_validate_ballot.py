#!/usr/bin/env python3
"""Fixtures for the Council Stage 5 ballot validator.

This script is nothing but checks, and it shipped with none of its own. Every
rule below is asserted in both directions -- a ballot that must pass and a
ballot that must fail for that specific reason -- because a validator that has
never rejected anything is not known to reject anything.

Writing them found one hole immediately: `REJECT: TRACES,` satisfied the rule
requiring a criterion AND a reason, because the check compared the number of
comma-separated fields rather than looking at the reason's content. A trailing
comma was a reason. So was `REJECT: TRACES,,,,`.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "bin" / "validate-ballot.py"


class ValidateBallotTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.ballot = pathlib.Path(self._tmp.name) / "ballot.txt"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_validator(self, body: str, items: int = 1, unresolved: str = "none"):
        self.ballot.write_text(body)
        return subprocess.run(
            [
                sys.executable, str(SCRIPT),
                "--items", str(items),
                "--unresolved", unresolved,
                str(self.ballot),
            ],
            capture_output=True, text=True,
        )

    def assertAccepted(self, body: str, **kw) -> None:
        proc = self.run_validator(body, **kw)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def assertRejected(self, body: str, because: str, **kw) -> None:
        proc = self.run_validator(body, **kw)
        self.assertEqual(proc.returncode, 1, "accepted but should not be:\n" + body)
        self.assertIn(because, proc.stderr)

    # --- the control -----------------------------------------------------
    def test_a_well_formed_ballot_is_accepted(self) -> None:
        # Without this every rejection test below is satisfied by a validator
        # that refuses everything.
        self.assertAccepted(
            "## Stage 5 ballots\nVoter 1:\n"
            "item 1: APPROVE\n"
            "item 2: QUALIFY: needs a smaller scope\n"
            "item 3: REJECT: TRACES, no evidence it was ever hit\n",
            items=3,
        )

    # --- REJECT must carry a criterion AND a reason ----------------------
    def test_reject_needs_a_criterion(self) -> None:
        self.assertRejected(
            "item 1: REJECT: this is just prose\n", "must name a valid criterion"
        )

    def test_reject_needs_a_reason(self) -> None:
        self.assertRejected("item 1: REJECT: TRACES\n", "give a reason")

    def test_reject_of_only_criteria_is_not_a_reason(self) -> None:
        self.assertRejected(
            "item 1: REJECT: TRACES, COST-PROPORTIONATE\n", "give a reason"
        )

    def test_trailing_comma_is_not_a_reason(self) -> None:
        # The hole this fixture was written for. Red against the pre-fix script.
        self.assertRejected("item 1: REJECT: TRACES,\n", "give a reason")

    def test_a_run_of_empty_fields_is_not_a_reason(self) -> None:
        self.assertRejected("item 1: REJECT: TRACES,,,,\n", "give a reason")

    def test_whitespace_only_field_is_not_a_reason(self) -> None:
        self.assertRejected("item 1: REJECT: TRACES,    \n", "give a reason")

    def test_criteria_then_reason_is_accepted(self) -> None:
        # The green half of the pair: the fix must not reject valid REJECTs.
        self.assertAccepted(
            "item 1: REJECT: TRACES, COST-PROPORTIONATE, no trace and too dear\n"
        )

    def test_a_reason_containing_commas_is_accepted(self) -> None:
        self.assertAccepted(
            "item 1: REJECT: TRACES, the cost, which is high, is unjustified\n"
        )

    # --- APPROVE cannot stand over UNRESOLVED MATERIAL -------------------
    def test_approve_over_unresolved_is_rejected(self) -> None:
        self.assertRejected(
            "item 1: APPROVE\n", "conflicts with UNRESOLVED MATERIAL", unresolved="1"
        )

    def test_qualify_over_unresolved_is_allowed(self) -> None:
        self.assertAccepted("item 1: QUALIFY: still open\n", unresolved="1")

    def test_unresolved_outside_the_item_range_is_rejected(self) -> None:
        self.assertRejected(
            "item 1: APPROVE\n", "outside --items", unresolved="5"
        )

    # --- coverage of the item set ----------------------------------------
    def test_missing_item_ballot_is_rejected(self) -> None:
        self.assertRejected("item 1: APPROVE\n", "missing item ballots: 2", items=2)

    def test_empty_ballot_is_rejected_rather_than_vacuously_accepted(self) -> None:
        # An empty file has no malformed line to trip any per-line rule; only
        # the coverage check stands between it and a clean exit.
        self.assertRejected("", "missing item ballots: 1")

    def test_duplicate_item_is_rejected(self) -> None:
        self.assertRejected(
            "item 1: APPROVE\nitem 1: QUALIFY: x\nitem 2: APPROVE\n",
            "appears more than once", items=2,
        )

    def test_item_outside_the_range_is_rejected(self) -> None:
        self.assertRejected("item 2: APPROVE\n", "outside the collated item range")

    def test_unstructured_line_is_rejected(self) -> None:
        self.assertRejected(
            "item 1: APPROVE\nI abstain on the rest\n", "not a structured item ballot"
        )

    # --- CLI surface ------------------------------------------------------
    def test_missing_ballot_file_is_rejected(self) -> None:
        proc = subprocess.run(
            [
                sys.executable, str(SCRIPT), "--items", "1",
                "--unresolved", "none", str(self.ballot.parent / "absent.txt"),
            ],
            capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("ballot file not found", proc.stderr)

    def test_unparseable_unresolved_is_rejected(self) -> None:
        self.assertRejected(
            "item 1: APPROVE\n", "comma-separated list", unresolved="one,two"
        )

    def test_non_positive_items_is_rejected(self) -> None:
        self.assertRejected("item 1: APPROVE\n", "--items must be positive", items=0)


if __name__ == "__main__":
    unittest.main()
