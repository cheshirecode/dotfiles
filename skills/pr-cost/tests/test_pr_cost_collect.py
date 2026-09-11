#!/usr/bin/env python3
"""Tests for the pr-cost collector CLI."""

from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest


SKILL_DIR = pathlib.Path(__file__).parents[1]
SCRIPT = SKILL_DIR / "scripts" / "pr_cost_collect.py"
FIXTURES = SKILL_DIR / "tests" / "fixtures"


class PrCostCollectTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temporary_path = pathlib.Path(self.temporary_directory.name)
        self.ledger = self.temporary_path / "ledger.jsonl"

    def run_cli(
        self,
        *arguments: str,
        stdin_text: str | None = None,
        env: dict[str, str] | None = None,
        expected_returncode: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            input=stdin_text,
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected_returncode,
            msg=f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
        )
        return result

    def make_failing_gh_stub(self) -> tuple[pathlib.Path, pathlib.Path]:
        stub_directory = self.temporary_path / "bin"
        stub_directory.mkdir()
        marker = self.temporary_path / "gh-called.txt"
        script = stub_directory / "gh"
        script.write_text(
            "#!/bin/sh\n"
            f"echo called > {marker}\n"
            "exit 99\n",
            encoding="utf-8",
        )
        script.chmod(script.stat().st_mode | stat.S_IXUSR)
        return stub_directory, marker

    def test_emit_valid_fixture(self) -> None:
        result = self.run_cli(
            "emit",
            "--fixture",
            str(FIXTURES / "emit_valid.json"),
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["schema_version"], "pr-cost/v1")
        self.assertEqual(payload["harness"], "claude")
        self.assertEqual(payload["confidence"], "estimated")
        self.assertEqual(payload["usd"], 1.23)

    def test_from_hook_rejects_gh_pr_view(self) -> None:
        result = self.run_cli(
            "from-hook",
            "--harness",
            "cursor",
            "--ledger",
            str(self.ledger),
            stdin_text=(FIXTURES / "hook_cursor_pr_view.json").read_text(),
        )
        response = json.loads(result.stdout)
        self.assertEqual(response["status"], "ignored")
        self.assertEqual(response["reason"], "not-pr-create")
        self.assertFalse(self.ledger.exists())

    def test_from_hook_writes_ledger_without_calling_gh_when_live_unset(self) -> None:
        stub_directory, marker = self.make_failing_gh_stub()
        env = os.environ.copy()
        env["PATH"] = f"{stub_directory}:{env.get('PATH', '')}"
        result = self.run_cli(
            "from-hook",
            "--harness",
            "cursor",
            "--ledger",
            str(self.ledger),
            stdin_text=(FIXTURES / "hook_cursor_pr_create.json").read_text(),
            env=env,
        )
        response = json.loads(result.stdout)
        self.assertEqual(response["status"], "annotated")
        self.assertFalse(response["commented"])
        self.assertTrue(self.ledger.exists())
        rows = [json.loads(line) for line in self.ledger.read_text().splitlines() if line.strip()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["harness"], "cursor")
        self.assertEqual(rows[0]["pr_url"], "https://github.com/cheshirecode/dotfiles/pull/123")
        self.assertFalse(marker.exists(), "gh should not run when PR_COST_HOOK_LIVE is unset")

    def test_annotate_is_idempotent_for_same_pr_and_session(self) -> None:
        base_arguments = (
            "annotate",
            "--fixture",
            str(FIXTURES / "emit_valid.json"),
            "--ledger",
            str(self.ledger),
        )
        first = json.loads(self.run_cli(*base_arguments).stdout)
        second = json.loads(self.run_cli(*base_arguments).stdout)
        self.assertEqual(first["status"], "annotated")
        self.assertEqual(second["status"], "duplicate")
        rows = [json.loads(line) for line in self.ledger.read_text().splitlines() if line.strip()]
        self.assertEqual(len(rows), 1)

    def test_allow_duplicate_publishes_a_corrected_figure(self) -> None:
        # The guard keys on pr_url + session_id, so the annotate that carries
        # a corrected number for the same session was refused -- the case
        # someone hits first after learning their posted figure was priced
        # wrong. The corrected row is appended, not substituted, so the ledger
        # keeps what was published and what replaced it.
        base_arguments = (
            "annotate",
            "--fixture",
            str(FIXTURES / "emit_valid.json"),
            "--ledger",
            str(self.ledger),
        )
        first = json.loads(self.run_cli(*base_arguments).stdout)
        corrected = json.loads(self.run_cli(*base_arguments, "--allow-duplicate").stdout)
        self.assertEqual(first["status"], "annotated")
        self.assertEqual(corrected["status"], "corrected")
        rows = [json.loads(line) for line in self.ledger.read_text().splitlines() if line.strip()]
        self.assertEqual(len(rows), 2, "the corrected row must be appended, not swapped in")

    def test_from_hook_has_no_allow_duplicate_escape(self) -> None:
        # A hook that re-fires must stay idempotent, or one retried PR create
        # posts the cost twice. The flag exists on annotate only.
        result = self.run_cli(
            "from-hook",
            "--harness",
            "cursor",
            "--ledger",
            str(self.ledger),
            "--allow-duplicate",
            stdin_text=(FIXTURES / "hook_cursor_pr_create.json").read_text(),
            expected_returncode=2,
        )
        self.assertIn("--allow-duplicate", result.stderr)


if __name__ == "__main__":
    unittest.main()
