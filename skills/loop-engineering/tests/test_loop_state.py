#!/usr/bin/env python3
"""Fixtures for the loop-engineering state CLI."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "loop_state.py"


class LoopStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.state = pathlib.Path(self.temporary_directory.name) / "loop.json"

    def run_cli(
        self,
        *arguments: str,
        expected_returncode: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def initialize(self, limit: int = 2) -> dict[str, object]:
        result = self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "targeted test passes",
            "--evidence",
            "failure reproduced",
            "--budget-unit",
            "hypotheses",
            "--budget-limit",
            str(limit),
            "--next-action",
            "test timing hypothesis",
            "--allowed-effect",
            "edit worktree",
        )
        return json.loads(result.stdout)

    def test_init_and_validate(self) -> None:
        state = self.initialize()
        self.assertEqual(state["terminal_status"], "running")
        self.assertEqual(state["budget"]["used"], 0)
        self.run_cli("validate", "--state", str(self.state))

    def test_init_refuses_to_overwrite_existing_state(self) -> None:
        self.initialize()
        result = self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "different goal",
            "--evidence",
            "none",
            "--budget-unit",
            "turns",
            "--budget-limit",
            "1",
            "--next-action",
            "stop",
            expected_returncode=2,
        )
        self.assertIn("refusing to overwrite", result.stderr)

    def test_advance_exhausts_budget_without_claiming_complete(self) -> None:
        self.initialize(limit=1)
        result = self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "timing hypothesis falsified",
            "--next-action",
            "handoff with evidence",
        )
        state = json.loads(result.stdout)
        self.assertEqual(state["terminal_status"], "budget_exhausted")
        self.assertNotEqual(state["terminal_status"], "complete")

    def test_complete_requires_verification_and_failed_transition_is_atomic(
        self,
    ) -> None:
        self.initialize()
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "agent says fixed",
            expected_returncode=2,
        )
        self.assertIn("requires --verification", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_complete_records_external_verification(self) -> None:
        self.initialize()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "three consecutive passes",
            "--verification",
            "pytest log artifact: /tmp/targeted-test.log",
            "--next-action",
            "checkpoint worklog",
        )
        state = json.loads(result.stdout)
        self.assertEqual(state["terminal_status"], "complete")
        self.assertIn("pytest log", state["verification"])

    def test_annotate_corrects_terminal_evidence_without_reopening(self) -> None:
        self.initialize(limit=1)
        exhausted = json.loads(
            self.run_cli(
                "advance",
                "--state",
                str(self.state),
                "--evidence",
                "no Git metadata",
                "--next-action",
                "obtain target repository",
            ).stdout
        )
        corrected = json.loads(
            self.run_cli(
                "annotate",
                "--state",
                str(self.state),
                "--evidence",
                "correction: cwd has .git but is not the target repository",
            ).stdout
        )
        self.assertEqual(corrected["terminal_status"], "budget_exhausted")
        self.assertEqual(corrected["budget"], exhausted["budget"])
        self.assertEqual(corrected["history"][-1]["event"], "annotated")


if __name__ == "__main__":
    unittest.main()
