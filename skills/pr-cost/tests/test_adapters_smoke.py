"""Adapter smoke tests running THE CODE UNDER REVIEW.

The previous suite shelled into a hardcoded /Users/... installed copy, so it
tested a different checkout than the diff (and failed everywhere else —
PR-31 council item 2). The adapter now resolves interpreter and collector
from its own location, so invoking the worktree adapter exercises the
worktree collector.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[1]
ADAPTER = SKILL / "adapters" / "claude" / "v1" / "pr_cost_from_hook.py"
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"


class ClaudeAdapterSmokeTest(unittest.TestCase):
    def run_adapter(self, stdin, ledger):
        env = {**os.environ, "PR_COST_LEDGER": str(ledger)}
        env.pop("PR_COST_HOOK_LIVE", None)
        return subprocess.run([sys.executable, str(ADAPTER)],
                              input=stdin, capture_output=True, text=True, env=env)

    def test_pr_create_payload_lands_in_ledger(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            r = self.run_adapter((FIXTURES / "hook_claude_pr_create.json").read_text(), ledger)
            self.assertEqual(r.returncode, 0, r.stderr)
            rows = [json.loads(l) for l in ledger.read_text().splitlines()]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["harness"], "claude")
            self.assertEqual(rows[0]["session_id"], "claude-session-fixture")
            # PostToolUse payloads carry no usage fields (council item 10):
            # the automatic path must say so, not invent numbers.
            self.assertIsNone(rows[0]["usd"])
            self.assertEqual(rows[0]["confidence"], "unavailable")

    def test_non_pr_command_writes_nothing(self):
        payload = json.loads((FIXTURES / "hook_claude_pr_create.json").read_text())
        payload["tool_input"]["command"] = "ls -la"
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            r = self.run_adapter(json.dumps(payload), ledger)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(ledger.exists())

    def test_garbage_stdin_fails_open(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            r = self.run_adapter("not json at all", ledger)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(ledger.exists())


class SessionUsageTest(unittest.TestCase):
    """claude_session_usage.py finally gets a caller-shaped test (item 3):
    it is the manual flow's engine and previously had zero tests."""

    def test_sums_unique_assistant_usage(self):
        rows = [
            {"sessionId": "s1", "timestamp": "2026-09-01T10:00:00Z",
             "message": {"role": "assistant", "id": "m1", "model": "test-model",
                         "usage": {"input_tokens": 100, "output_tokens": 20}}},
            # duplicate message id must not double-count
            {"sessionId": "s1", "timestamp": "2026-09-01T10:01:00Z",
             "message": {"role": "assistant", "id": "m1", "model": "test-model",
                         "usage": {"input_tokens": 100, "output_tokens": 20}}},
            {"sessionId": "s1", "timestamp": "2026-09-01T10:02:00Z",
             "message": {"role": "assistant", "id": "m2", "model": "test-model",
                         "usage": {"input_tokens": 50, "output_tokens": 5}}},
        ]
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
            f.write("\n".join(json.dumps(r) for r in rows))
        try:
            r = subprocess.run(
                [sys.executable, str(SKILL / "scripts" / "claude_session_usage.py"), "--jsonl", f.name],
                capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            out = json.loads(r.stdout)
            self.assertEqual(out["tokens_in"], 150)
            self.assertEqual(out["tokens_out"], 25)
            self.assertEqual(out["session_id"], "s1")
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
