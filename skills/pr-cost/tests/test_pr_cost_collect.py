#!/usr/bin/env python3
"""Tests for the pr-cost collector CLI."""

from __future__ import annotations

import importlib.util
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

SPEC = importlib.util.spec_from_file_location("pr_cost_collect", SCRIPT)
collector = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(collector)


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
        # Distinct figures, because the point of the flag is that the second
        # one is a correction: the original posted number was priced wrong.
        first = json.loads(self.run_cli(*base_arguments, "--usd", "517.46").stdout)
        duplicate = json.loads(self.run_cli(*base_arguments, "--usd", "517.46").stdout)
        corrected = json.loads(
            self.run_cli(*base_arguments, "--usd", "602.99", "--allow-duplicate").stdout
        )
        self.assertEqual(first["status"], "annotated")
        # Without the flag the default stays idempotent, so a re-firing hook
        # cannot post twice.
        self.assertEqual(duplicate["status"], "duplicate")
        self.assertEqual(corrected["status"], "corrected")
        rows = [json.loads(line) for line in self.ledger.read_text().splitlines() if line.strip()]
        # Assert the figures, not just the count: two rows holding the same
        # wrong number would satisfy a length check while losing the
        # correction entirely.
        self.assertEqual([row["usd"] for row in rows], [517.46, 602.99])

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

    # The posted comment has to be readable, not just correct.

    def test_comment_body_shows_the_split_the_basis_and_the_scope(self) -> None:
        # The reported defect: the JSON put tokens_in next to usd with nothing
        # between them, so a reader multiplied one by the input rate. The
        # figures here are the session that produced that comment.
        body = collector.comment_body(
            {
                "schema_version": "pr-cost/v1",
                "harness": "claude",
                "confidence": "estimated",
                "usd": 602.99,
                "tokens_in": 720_696_122,
                "tokens_in_uncached": 2_956,
                "tokens_in_cache_read": 697_885_763,
                "tokens_in_cache_write": 22_807_403,
                "tokens_out": 1_038_408,
                "usd_basis": "model-rates",
                "scope": "session-total",
                "model": "claude-opus-5",
                "session_id": "s",
                "window_start": "2026-01-01T00:00:00+00:00",
                "window_end": "2026-01-01T00:01:00+00:00",
                "pr_url": None,
                "generated_at": "2026-01-01T00:01:00+00:00",
            }
        )
        # Assert on the prose above the JSON block: the JSON always held these
        # numbers, so matching the whole body would pass on the old comment.
        heading = body.split("```json")[0]
        self.assertIn("697,885,763 cache read", heading)
        self.assertIn("96.8% of input", heading)
        self.assertIn("model-rates", heading)
        self.assertIn("may cover other PRs", heading)

    def test_a_split_that_does_not_sum_to_tokens_in_is_refused(self) -> None:
        # A split that does not add up is worse than no split: both numbers
        # are then in the comment and a reader cannot tell which to believe.
        payload = {
            "schema_version": "pr-cost/v1",
            "harness": "claude",
            "confidence": "estimated",
            "usd": 1.0,
            "tokens_in": 1_000,
            "tokens_in_uncached": 100,
            "tokens_in_cache_read": 100,
            "tokens_in_cache_write": 100,
            "tokens_out": 10,
            "model": "claude-opus-5",
            "session_id": "s",
            "window_start": "2026-01-01T00:00:00+00:00",
            "window_end": "2026-01-01T00:01:00+00:00",
            "pr_url": None,
            "generated_at": "2026-01-01T00:01:00+00:00",
        }
        with self.assertRaises(collector.PrCostError):
            collector.validate_payload(payload)

    def test_scope_defaults_to_session_total_when_tokens_are_present(self) -> None:
        # A session reader sums the whole session, which may cover several PRs
        # and unrelated work. Unlabelled, those numbers read as this PR's cost.
        result = self.run_cli(
            "emit",
            "--harness",
            "claude",
            "--confidence",
            "estimated",
            "--usd",
            "1.0",
            "--tokens-in",
            "100",
            "--tokens-out",
            "10",
            "--model",
            "claude-opus-5",
            "--session-id",
            "s",
        )
        self.assertEqual(json.loads(result.stdout)["scope"], "session-total")


if __name__ == "__main__":
    unittest.main()
