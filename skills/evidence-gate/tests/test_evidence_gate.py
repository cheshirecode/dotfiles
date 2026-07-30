#!/usr/bin/env python3
"""Fixtures for the evidence-gate CLI."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "evidence_gate.py"


class EvidenceGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.gate = pathlib.Path(self.temporary_directory.name) / "gate.json"

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

    def initialize(self) -> None:
        self.run_cli(
            "init",
            "--gate",
            str(self.gate),
            "--goal",
            "change is verified and merged",
            "--criterion",
            "tests=full suite passes",
            "--criterion",
            "merge=PR is merged into main",
        )

    def test_check_rejects_uncovered_criterion(self) -> None:
        self.initialize()
        self.run_cli(
            "record",
            "--gate",
            str(self.gate),
            "--criterion",
            "tests",
            "--kind",
            "command",
            "--ref",
            "tests/run.sh all",
            "--result",
            "62 pass, 0 fail",
        )
        report = json.loads(
            self.run_cli(
                "check",
                "--gate",
                str(self.gate),
                expected_returncode=1,
            ).stdout
        )
        self.assertEqual(report["status"], "unsatisfied")
        self.assertEqual(report["missing"], ["merge"])
        self.assertEqual(report["verification"], "")

    def test_check_returns_digest_when_every_criterion_is_covered(self) -> None:
        self.initialize()
        for criterion, kind, reference, result in (
            ("tests", "command", "tests/run.sh all", "62 pass, 0 fail"),
            (
                "merge",
                "github",
                "https://github.com/cheshirecode/dotfiles/pull/7",
                "merged into main",
            ),
        ):
            self.run_cli(
                "record",
                "--gate",
                str(self.gate),
                "--criterion",
                criterion,
                "--kind",
                kind,
                "--ref",
                reference,
                "--result",
                result,
            )
        report = json.loads(self.run_cli("check", "--gate", str(self.gate)).stdout)
        self.assertEqual(report["status"], "satisfied")
        self.assertEqual(report["missing"], [])
        self.assertIn("#sha256=", report["verification"])

    def test_unknown_criterion_fails_without_mutation(self) -> None:
        self.initialize()
        before = self.gate.read_text()
        self.run_cli(
            "record",
            "--gate",
            str(self.gate),
            "--criterion",
            "deploy",
            "--kind",
            "artifact",
            "--ref",
            "/tmp/deploy.log",
            "--result",
            "passed",
            expected_returncode=2,
        )
        self.assertEqual(self.gate.read_text(), before)

    def test_duplicate_criterion_is_rejected(self) -> None:
        self.run_cli(
            "init",
            "--gate",
            str(self.gate),
            "--goal",
            "duplicate test",
            "--criterion",
            "tests=first",
            "--criterion",
            "tests=second",
            expected_returncode=2,
        )
        self.assertFalse(self.gate.exists())

    def test_init_refuses_overwrite(self) -> None:
        self.initialize()
        self.run_cli(
            "init",
            "--gate",
            str(self.gate),
            "--goal",
            "different goal",
            "--criterion",
            "tests=passes",
            expected_returncode=2,
        )

    def test_init_force_overwrites_existing_gate(self) -> None:
        self.initialize()
        before = self.gate.read_text()
        self.run_cli(
            "init",
            "--gate",
            str(self.gate),
            "--goal",
            "replacement goal",
            "--criterion",
            "replace=replaces",
            "--force",
        )
        after = json.loads(self.gate.read_text())
        self.assertEqual(after["goal"], "replacement goal")
        self.assertNotEqual(self.gate.read_text(), before)


if __name__ == "__main__":
    unittest.main()
