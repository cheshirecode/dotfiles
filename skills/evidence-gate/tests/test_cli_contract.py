#!/usr/bin/env python3
"""Verify the evidence-gate CLI used by completion workflows.

Executable loop-engineering documentation covers its cross-skill consumer.
These tests preserve parser flags, verification output and rejection behavior.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "evidence_gate.py"


class CliContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.gate = pathlib.Path(self._tmp.name) / "gate.json"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_gate(self, *args: str):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args], capture_output=True, text=True
        )

    def seed(self, covered: bool = True) -> None:
        proc = self.run_gate(
            "init", "--gate", str(self.gate), "--goal", "ship it",
            "--criterion", "c1=the thing works",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        if covered:
            proc = self.run_gate(
                "record", "--gate", str(self.gate), "--criterion", "c1",
                "--kind", "command", "--ref", "pytest", "--result", "6 pass",
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)

    # --- the surface loop-engineering was told about ---------------------
    def test_quiet_exists_on_check_and_show(self) -> None:
        for sub in ("check", "show"):
            with self.subTest(sub):
                proc = self.run_gate(sub, "--help")
                self.assertIn("--quiet", proc.stdout)

    def test_quiet_does_not_exist_on_init_and_record(self) -> None:
        # The reason the sibling skill tells callers to redirect stdout
        # instead. If --quiet appears here, that instruction becomes clumsy
        # advice rather than the only option -- and the note should move too.
        for sub in ("init", "record"):
            with self.subTest(sub):
                proc = self.run_gate(sub, "--help")
                self.assertNotIn("--quiet", proc.stdout)

    def test_plain_check_carries_the_verification_value(self) -> None:
        self.seed()
        proc = self.run_gate("check", "--gate", str(self.gate))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "satisfied")
        self.assertTrue(payload["verification"].startswith("evidence-gate:"))
        self.assertIn("sha256=", payload["verification"])

    def test_quiet_check_omits_the_verification_value(self) -> None:
        # Both halves matter. If --quiet ever grew the verification value the
        # sibling instruction would be wrong but harmless; if plain check ever
        # lost it, a loop's --verification records nothing and the run still
        # reports complete.
        self.seed()
        proc = self.run_gate("check", "--gate", str(self.gate), "--quiet")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("sha256=", proc.stdout)
        self.assertEqual(proc.stdout.strip(), "satisfied 1/1")

    def test_unsatisfied_check_exits_1_as_a_verdict(self) -> None:
        # recording.md: "exit 1 is the verdict, not a failure."
        self.seed(covered=False)
        proc = self.run_gate("check", "--gate", str(self.gate))
        self.assertEqual(proc.returncode, 1)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "unsatisfied")
        self.assertEqual(payload["verification"], "")

    # --- validate_gate's own rules ---------------------------------------
    def corrupt(self, mutate) -> subprocess.CompletedProcess:
        self.seed()
        gate = json.loads(self.gate.read_text())
        mutate(gate)
        self.gate.write_text(json.dumps(gate))
        return self.run_gate("check", "--gate", str(self.gate))

    def assertRefused(self, mutate, because: str) -> None:
        proc = self.corrupt(mutate)
        self.assertNotEqual(proc.returncode, 0, "accepted a malformed gate")
        self.assertIn(because, proc.stderr + proc.stdout)

    def test_wrong_schema_version_is_refused(self) -> None:
        self.assertRefused(
            lambda g: g.__setitem__("schema_version", 99), "schema_version"
        )

    def test_empty_goal_is_refused(self) -> None:
        self.assertRefused(lambda g: g.__setitem__("goal", "   "), "goal")

    def test_empty_criteria_is_refused_not_vacuously_satisfied(self) -> None:
        # A gate with no criteria has nothing missing. Without this rule it
        # would report satisfied and hand back a verification digest.
        self.assertRefused(lambda g: g.__setitem__("criteria", {}), "non-empty")

    def test_evidence_must_be_a_list(self) -> None:
        self.assertRefused(
            lambda g: g["criteria"]["c1"].__setitem__("evidence", "yes"), "list"
        )

    def test_evidence_record_with_empty_result_is_refused(self) -> None:
        self.assertRefused(
            lambda g: g["criteria"]["c1"]["evidence"][0].__setitem__("result", "  "),
            "result",
        )

    def test_evidence_record_with_unknown_kind_is_refused(self) -> None:
        self.assertRefused(
            lambda g: g["criteria"]["c1"]["evidence"][0].__setitem__("kind", "vibes"),
            "kind",
        )

    def test_an_untouched_gate_still_passes(self) -> None:
        # The control for the seven refusals above: they must be rejecting the
        # mutation, not the fixture's own gate-writing.
        proc = self.corrupt(lambda g: None)
        self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main()
