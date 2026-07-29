#!/usr/bin/env python3
"""Fixtures for the loop-engineering state CLI."""

from __future__ import annotations

import hashlib
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
        self.successor = pathlib.Path(self.temporary_directory.name) / "successor.json"

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

    def fingerprint(self) -> str:
        return self.run_cli(
            "fingerprint",
            "--state",
            str(self.state),
        ).stdout.strip()

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
            expected_returncode=3,
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

    def test_resume_creates_bound_successor_without_reopening_blocker(self) -> None:
        self.initialize()
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "needs_human",
            "--evidence",
            "deployment credential requires intervention",
            "--next-action",
            "ask operator to refresh the credential",
            "--consume",
            "1",
        )
        predecessor_text = self.state.read_text()
        result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "operator refreshed the credential",
            "--next-action",
            "replay the deployment verification",
            "--allowed-effect",
            "run deployment verification",
            "--approval-boundary",
            "use only the refreshed credential",
        )
        successor = json.loads(result.stdout)

        self.assertEqual(self.state.read_text(), predecessor_text)
        self.assertEqual(successor["terminal_status"], "running")
        self.assertEqual(successor["goal"], "targeted test passes")
        self.assertEqual(
            successor["budget"],
            {"unit": "hypotheses", "limit": 2, "used": 1},
        )
        self.assertEqual(
            successor["predecessor"]["terminal_status"],
            "needs_human",
        )
        self.assertEqual(
            json.loads(predecessor_text)["next_action"],
            "ask operator to refresh the credential",
        )
        self.assertEqual(
            successor["predecessor"]["sha256"],
            hashlib.sha256(predecessor_text.encode()).hexdigest(),
        )
        self.assertEqual(successor["history"][-1]["event"], "resumed:needs_human")
        self.assertIn("edit worktree", successor["allowed_effects"])
        self.assertIn("run deployment verification", successor["allowed_effects"])

    def test_resume_rejects_running_and_complete_predecessors(self) -> None:
        self.initialize()
        running_result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "no intervention occurred",
            "--next-action",
            "continue current run",
            expected_returncode=3,
        )
        self.assertIn("cannot resume state with status: running", running_result.stderr)
        self.assertFalse(self.successor.exists())

        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "complete",
            "--evidence",
            "targeted test passed",
            "--verification",
            "test log",
        )
        complete_result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "request to reopen completed work",
            "--next-action",
            "do not reopen",
            expected_returncode=3,
        )
        self.assertIn(
            "cannot resume state with status: complete", complete_result.stderr
        )
        self.assertFalse(self.successor.exists())

    def test_exhausted_resume_requires_explicit_budget_extension(self) -> None:
        self.initialize(limit=1)
        self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "initial hypothesis falsified",
            "--next-action",
            "request authority for another hypothesis",
        )
        rejected = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "no additional budget authorized",
            "--next-action",
            "remain exhausted",
            expected_returncode=3,
        )
        self.assertIn("requires --extend-budget", rejected.stderr)
        self.assertFalse(self.successor.exists())

        resumed = json.loads(
            self.run_cli(
                "resume",
                "--state",
                str(self.state),
                "--new-state",
                str(self.successor),
                "--evidence",
                "operator authorized two more hypotheses",
                "--extend-budget",
                "2",
                "--next-action",
                "test the next hypothesis",
            ).stdout
        )
        self.assertEqual(
            resumed["budget"],
            {"unit": "hypotheses", "limit": 3, "used": 1},
        )

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
            expected_returncode=3,
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
            "--consume",
            "1",
        )
        state = json.loads(result.stdout)
        self.assertEqual(state["terminal_status"], "complete")
        self.assertIn("pytest log", state["verification"])
        self.assertEqual(state["budget"]["used"], 1)
        self.assertEqual(state["next_action"], "")
        self.assertEqual(state["history"][-1]["next_action"], "")

    def test_non_resumable_finish_rejects_explicit_next_action_atomically(
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
            "targeted test passed",
            "--verification",
            "pytest log",
            "--next-action",
            "stale follow-up",
            expected_returncode=3,
        )
        self.assertIn("complete does not accept --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_resumable_finish_requires_actionable_next_step(self) -> None:
        self.initialize()
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "credential unavailable",
            expected_returncode=3,
        )
        self.assertIn("blocked requires --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_cancelled_finish_clears_running_next_action(self) -> None:
        self.initialize()
        state = json.loads(
            self.run_cli(
                "finish",
                "--state",
                str(self.state),
                "--status",
                "cancelled",
                "--evidence",
                "operator cancelled the run",
            ).stdout
        )
        self.assertEqual(state["terminal_status"], "cancelled")
        self.assertEqual(state["next_action"], "")

    def test_annotate_rejects_next_action_for_non_resumable_terminal(self) -> None:
        self.initialize()
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "cancelled",
            "--evidence",
            "operator cancelled the run",
        )
        expected_sha256 = self.fingerprint()
        before = self.state.read_text()
        result = self.run_cli(
            "annotate",
            "--state",
            str(self.state),
            "--expect-sha256",
            expected_sha256,
            "--evidence",
            "correction: cancellation was explicit",
            "--next-action",
            "reopen the cancelled run",
            expected_returncode=3,
        )
        self.assertIn("cancelled does not accept --next-action", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_runtime_rejection_and_cli_misuse_are_distinct_and_atomic(self) -> None:
        self.initialize(limit=1)
        before = self.state.read_text()
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "two retries attempted",
            "--next-action",
            "request another retry",
            "--consume",
            "2",
            expected_returncode=3,
        )
        self.assertIn("only 1 remain", result.stderr)
        self.assertEqual(self.state.read_text(), before)

        misuse = self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "invalid zero-unit transition",
            "--next-action",
            "fix invocation",
            "--consume",
            "0",
            expected_returncode=2,
        )
        self.assertIn("usage:", misuse.stderr)
        self.assertNotIn("loop-state:", misuse.stderr)
        self.assertEqual(self.state.read_text(), before)

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
        expected_sha256 = self.fingerprint()
        corrected = json.loads(
            self.run_cli(
                "annotate",
                "--state",
                str(self.state),
                "--expect-sha256",
                expected_sha256,
                "--evidence",
                "correction: cwd has .git but is not the target repository",
            ).stdout
        )
        self.assertEqual(corrected["terminal_status"], "budget_exhausted")
        self.assertEqual(corrected["budget"], exhausted["budget"])
        self.assertEqual(corrected["history"][-1]["event"], "annotated")

    def test_fingerprint_matches_exact_state_bytes(self) -> None:
        self.initialize()

        self.assertEqual(
            self.fingerprint(),
            hashlib.sha256(self.state.read_bytes()).hexdigest(),
        )

    def test_annotate_rejects_stale_fingerprint_atomically(self) -> None:
        self.initialize()
        stale_sha256 = self.fingerprint()
        self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "another session advanced the run",
            "--next-action",
            "continue from the newer snapshot",
        )
        before = self.state.read_text()

        result = self.run_cli(
            "annotate",
            "--state",
            str(self.state),
            "--expect-sha256",
            stale_sha256,
            "--evidence",
            "stale session correction",
            expected_returncode=3,
        )

        self.assertIn("state fingerprint changed", result.stderr)
        self.assertEqual(self.state.read_text(), before)


if __name__ == "__main__":
    unittest.main()
