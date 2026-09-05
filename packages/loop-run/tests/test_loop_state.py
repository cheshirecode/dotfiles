#!/usr/bin/env python3
"""Fixtures for the loop-engineering state CLI."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "src" / "looprun" / "loop_state.py"
SKILL = SCRIPT.parents[1] / "SKILL.md"
ORCHESTRATOR = SCRIPT.parents[1] / "references/orchestrator.md"

# Heading anchors shared by multiple tests: a rename is one edit here, and a
# missing heading fails with its name rather than a bare IndexError
# (commit 44f3f78 repointed the same literal in three tests; cf. 81d4cd7).
H_DRIVE = "## Drive the loop — one call per cycle"
H_ORCHESTRATOR = "## Orchestrator mode"


def section(text: str, start: str, end: str | None = None) -> str:
    """Slice the document between two headings, naming any missing anchor."""
    assert start in text, f"heading {start!r} not found in document"
    body = text.split(start, 1)[1]
    if end is None:
        return body
    assert end in body, f"heading {end!r} not found after {start!r}"
    return body.split(end, 1)[0]
SPEC = importlib.util.spec_from_file_location("loop_state_under_test", SCRIPT)
assert SPEC and SPEC.loader
LOOP_STATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOOP_STATE)


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

    def test_init_force_overwrites_existing_state(self) -> None:
        self.initialize()
        before = self.state.read_text()
        self.run_cli(
            "init",
            "--state",
            str(self.state),
            "--goal",
            "replacement goal",
            "--evidence",
            "forced overwrite",
            "--budget-unit",
            "cycles",
            "--budget-limit",
            "5",
            "--next-action",
            "replaced",
            "--force",
        )
        after = json.loads(self.state.read_text())
        self.assertEqual(after["goal"], "replacement goal")
        self.assertNotEqual(self.state.read_text(), before)

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

    def test_advance_waits_for_state_lock(self) -> None:
        self.initialize()
        command = [
            sys.executable,
            str(SCRIPT),
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "serialized transition",
            "--next-action",
            "verify lock",
        ]
        with LOOP_STATE.state_lock(self.state):
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            with self.assertRaises(subprocess.TimeoutExpired):
                process.communicate(timeout=0.2)

        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, msg=f"stdout:\n{stdout}\nstderr:\n{stderr}")
        state = json.loads(self.state.read_text())
        self.assertIn("serialized transition", state["progress_evidence"])

    def test_concurrent_advances_preserve_every_transition(self) -> None:
        self.initialize(limit=8)
        processes = [
            subprocess.Popen(
                [
                    sys.executable,
                    str(SCRIPT),
                    "advance",
                    "--state",
                    str(self.state),
                    "--evidence",
                    f"writer-{index}",
                    "--next-action",
                    "continue",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for index in range(8)
        ]
        results = [process.communicate(timeout=10) for process in processes]
        for process, (stdout, stderr) in zip(processes, results):
            self.assertEqual(
                process.returncode,
                0,
                msg=f"stdout:\n{stdout}\nstderr:\n{stderr}",
            )

        state = json.loads(self.state.read_text())
        self.assertEqual(state["budget"]["used"], 8)
        for index in range(8):
            self.assertIn(f"writer-{index}", state["progress_evidence"])

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

    def test_malformed_state_inputs_exit_three_not_traceback(self) -> None:
        for payload in ("[]", "5", '"loop"'):
            self.state.write_text(payload)
            result = self.run_cli(
                "validate",
                "--state",
                str(self.state),
                expected_returncode=3,
            )
            self.assertIn("loop-state:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

        directory_state = pathlib.Path(self.temporary_directory.name) / "as-dir"
        directory_state.mkdir()
        result = self.run_cli(
            "validate",
            "--state",
            str(directory_state),
            expected_returncode=3,
        )
        self.assertIn("loop-state:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_validate_enforces_transition_invariants(self) -> None:
        base = self.initialize()
        cases = (
            (
                "running action",
                "running",
                " ",
                0,
                "",
                "running requires non-empty next_action",
            ),
            (
                "blocked action",
                "blocked",
                "",
                0,
                "",
                "blocked requires non-empty next_action",
            ),
            (
                "complete action",
                "complete",
                "stale follow-up",
                0,
                "test log",
                "complete requires empty next_action",
            ),
        )
        for name, status, next_action, used, verification, message in cases:
            with self.subTest(name=name):
                state = json.loads(json.dumps(base))
                state["terminal_status"] = status
                state["next_action"] = next_action
                state["budget"]["used"] = used
                state["verification"] = verification
                self.state.write_text(json.dumps(state))
                result = self.run_cli(
                    "validate",
                    "--state",
                    str(self.state),
                    expected_returncode=3,
                )
                self.assertIn(message, result.stderr)

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

    def test_annotate_rejects_blank_next_action_on_resumable_state(self) -> None:
        self.initialize(limit=2)
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "hit wall",
            "--next-action",
            "retry after fix",
        )
        fingerprint = self.fingerprint()
        before = self.state.read_text()

        result = self.run_cli(
            "annotate",
            "--state",
            str(self.state),
            "--expect-sha256",
            fingerprint,
            "--evidence",
            "correction",
            "--next-action",
            "  ",
            expected_returncode=3,
        )

        self.assertIn("--next-action must be non-empty", result.stderr)
        self.assertEqual(self.state.read_text(), before)

    def test_resume_of_budget_exhausted_status_requires_extension_even_below_ceiling(
        self,
    ) -> None:
        self.initialize(limit=9)
        self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "budget_exhausted",
            "--evidence",
            "declared exhausted early",
            "--next-action",
            "resume later",
            "--consume",
            "1",
        )

        result = self.run_cli(
            "resume",
            "--state",
            str(self.state),
            "--new-state",
            str(self.successor),
            "--evidence",
            "intervention supplied",
            "--next-action",
            "replay the blocked check",
            expected_returncode=3,
        )

        self.assertIn("requires --extend-budget", result.stderr)
        self.assertFalse(self.successor.exists())

    def test_quiet_emits_one_running_index_line(self) -> None:
        self.initialize(limit=2)
        result = self.run_cli(
            "advance",
            "--state",
            str(self.state),
            "--evidence",
            "step one done",
            "--next-action",
            "check step two",
            "--quiet",
        )
        lines = result.stdout.strip().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0], "running 1/2 hypotheses — next: check step two")

    def test_quiet_terminal_line_shows_verification_not_next_action(self) -> None:
        self.initialize(limit=2)
        result = self.run_cli(
            "finish",
            "--state",
            str(self.state),
            "--status",
            "blocked",
            "--evidence",
            "hit wall",
            "--next-action",
            "retry after fix",
            "--quiet",
        )
        line = result.stdout.strip()
        self.assertTrue(line.startswith("blocked 0/2 hypotheses"))
        self.assertNotIn("next:", line)


if __name__ == "__main__":
    unittest.main()
