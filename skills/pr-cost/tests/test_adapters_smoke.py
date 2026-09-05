#!/usr/bin/env python3
"""Smoke the three harness adapters without a live GitHub write."""

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
FIXTURES = SKILL_DIR / "tests" / "fixtures"
CURSOR_WRAPPER = SKILL_DIR / "adapters" / "cursor" / "pr-cost-from-hook.sh"
CLAUDE_ADAPTER = SKILL_DIR / "adapters" / "claude" / "v1" / "pr_cost_from_hook.py"
CODEX_GH = SKILL_DIR / "adapters" / "codex" / "bin" / "gh"


class AdapterSmokeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temporary_path = pathlib.Path(self.temporary_directory.name)
        self.ledger = self.temporary_path / "ledger.jsonl"

    def env_with_ledger(self) -> dict[str, str]:
        env = os.environ.copy()
        env["PR_COST_LEDGER"] = str(self.ledger)
        env.pop("PR_COST_HOOK_LIVE", None)
        return env

    def ledger_rows(self) -> list[dict[str, object]]:
        if not self.ledger.exists():
            return []
        return [
            json.loads(line)
            for line in self.ledger.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    def test_cursor_wrapper_writes_ledger(self) -> None:
        result = subprocess.run(
            [str(CURSOR_WRAPPER)],
            input=(FIXTURES / "hook_cursor_pr_create.json").read_text(encoding="utf-8"),
            capture_output=True,
            text=True,
            env=self.env_with_ledger(),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {})
        rows = self.ledger_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["harness"], "cursor")
        self.assertEqual(rows[0]["pr_url"], "https://github.com/cheshirecode/dotfiles/pull/123")

    def test_claude_adapter_writes_ledger(self) -> None:
        result = subprocess.run(
            [sys.executable, str(CLAUDE_ADAPTER)],
            input=(FIXTURES / "hook_claude_pr_create.json").read_text(encoding="utf-8"),
            capture_output=True,
            text=True,
            env=self.env_with_ledger(),
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.ledger_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["harness"], "claude")
        self.assertEqual(rows[0]["pr_url"], "https://github.com/cheshirecode/dotfiles/pull/124")

    def test_codex_gh_wrapper_writes_ledger_without_live_comment(self) -> None:
        stub_directory = self.temporary_path / "bin"
        stub_directory.mkdir()
        marker = self.temporary_path / "gh-comment-called.txt"
        real_gh = stub_directory / "gh"
        real_gh.write_text(
            "#!/bin/sh\n"
            "if [ \"$1\" = pr ] && [ \"$2\" = comment ]; then\n"
            f"  echo commented > {marker}\n"
            "  exit 99\n"
            "fi\n"
            "echo 'https://github.com/cheshirecode/dotfiles/pull/125'\n"
            "exit 0\n",
            encoding="utf-8",
        )
        real_gh.chmod(real_gh.stat().st_mode | stat.S_IXUSR)
        env = self.env_with_ledger()
        env["PR_COST_REAL_GH"] = str(real_gh)
        result = subprocess.run(
            [str(CODEX_GH), "pr", "create", "--title", "Fixture"],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://github.com/cheshirecode/dotfiles/pull/125", result.stdout)
        rows = self.ledger_rows()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["harness"], "codex")
        self.assertEqual(rows[0]["pr_url"], "https://github.com/cheshirecode/dotfiles/pull/125")
        self.assertFalse(marker.exists(), "gh pr comment must not run when live is unset")


if __name__ == "__main__":
    unittest.main()
