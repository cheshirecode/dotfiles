"""Collector tests. Every negative case here was proven red by mutation:
gutting validate_payload, forcing detect_harness constant, or corrupting a
merge field makes a named assertion below fail (PR-31 council items 1, 7, 9
lineage — this suite replaces one that stayed green through all three)."""

from __future__ import annotations

import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[1]
COLLECT = SKILL / "scripts" / "pr_cost_collect.py"
FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures"


def run_collect(args, stdin=None, env=None):
    merged_env = {**os.environ, **(env or {})}
    merged_env.pop("PR_COST_HOOK_LIVE", None)
    if env and "PR_COST_HOOK_LIVE" in env:
        merged_env["PR_COST_HOOK_LIVE"] = env["PR_COST_HOOK_LIVE"]
    return subprocess.run(
        [sys.executable, str(COLLECT), *args],
        input=stdin, capture_output=True, text=True, env=merged_env,
    )


class EmitTest(unittest.TestCase):
    def test_emit_valid_fixture_round_trips_every_field(self):
        expected = json.loads((FIXTURES / "emit_valid.json").read_text())
        r = run_collect(["emit", "--fixture", str(FIXTURES / "emit_valid.json")])
        self.assertEqual(r.returncode, 0, r.stderr)
        payload = json.loads(r.stdout)
        # Full-dict equality: a merge bug in ANY field fails here, not just
        # the four fields the old test spot-checked.
        self.assertEqual(payload, expected)

    def test_invalid_harness_is_rejected(self):
        r = run_collect(["emit", "--fixture", str(FIXTURES / "emit_valid.json"),
                         "--harness", "vibes"])
        self.assertEqual(r.returncode, 2)

    def test_wrong_typed_field_is_rejected(self):
        # A deleted window_start gets legitimately defaulted by emit, so the
        # discriminating negative is a type violation the merge cannot heal.
        broken = json.loads((FIXTURES / "emit_valid.json").read_text())
        broken["tokens_in"] = "lots"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(broken, f)
        try:
            r = run_collect(["emit", "--fixture", f.name])
            self.assertEqual(r.returncode, 2, r.stdout)
            self.assertIn("tokens_in", r.stderr)
        finally:
            os.unlink(f.name)

    def test_bad_pr_url_is_rejected(self):
        broken = json.loads((FIXTURES / "emit_valid.json").read_text())
        broken["pr_url"] = "https://example.com/not-a-pr"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(broken, f)
        try:
            r = run_collect(["emit", "--fixture", f.name])
            self.assertEqual(r.returncode, 2)
            self.assertIn("pr_url", r.stderr)
        finally:
            os.unlink(f.name)


class FromHookTest(unittest.TestCase):
    def hook(self, ledger, extra_args=(), env=None, payload_path=None):
        payload = (payload_path or (FIXTURES / "hook_claude_pr_create.json")).read_text()
        return run_collect(["from-hook", "--ledger", str(ledger), *extra_args],
                           stdin=payload, env=env)

    def test_raw_claude_payload_autodetects_harness(self):
        # No --harness flag on purpose: this drives detect_harness and the
        # native Bash branch (the branch shipped dead as "Shell" — item 1).
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            r = self.hook(ledger)
            self.assertEqual(r.returncode, 0, r.stderr)
            out = json.loads(r.stdout)
            self.assertEqual(out["status"], "annotated", out)
            self.assertEqual(out["payload"]["harness"], "claude")
            self.assertEqual(out["payload"]["pr_url"],
                             "https://github.com/cheshirecode/dotfiles/pull/124")

    def test_shape_without_harness_marker_fails_open_as_unknown(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            r = run_collect(["from-hook", "--ledger", str(ledger)],
                            stdin=json.dumps({"mystery": True}))
            self.assertEqual(r.returncode, 0)
            self.assertEqual(json.loads(r.stdout)["status"], "ignored")
            self.assertFalse(ledger.exists())

    def test_duplicate_session_pr_pair_is_not_reannotated(self):
        with tempfile.TemporaryDirectory() as d:
            ledger = pathlib.Path(d) / "ledger.jsonl"
            self.hook(ledger)
            r = self.hook(ledger)
            self.assertEqual(json.loads(r.stdout)["status"], "duplicate")
            self.assertEqual(len(ledger.read_text().splitlines()), 1)


class LiveCommentTest(unittest.TestCase):
    """End-to-end with a PATH-stubbed gh (council item 13): prove the
    annotation call actually happens in live mode with the marker body, and
    never happens otherwise."""

    def run_with_stub_gh(self, live):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            capture = d / "gh-args.json"
            stub = d / "gh"
            stub.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys, pathlib\n"
                f"pathlib.Path({str(capture)!r}).write_text(json.dumps(sys.argv[1:]))\n"
            )
            stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
            env = {"PATH": f"{d}:{os.environ['PATH']}"}
            if live:
                env["PR_COST_HOOK_LIVE"] = "1"
            ledger = d / "ledger.jsonl"
            r = run_collect(["from-hook", "--ledger", str(ledger)],
                            stdin=(FIXTURES / "hook_claude_pr_create.json").read_text(),
                            env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            return json.loads(r.stdout), (json.loads(capture.read_text()) if capture.exists() else None)

    def test_live_mode_posts_marker_comment(self):
        out, gh_args = self.run_with_stub_gh(live=True)
        self.assertTrue(out["commented"], out)
        self.assertIsNotNone(gh_args, "gh was never invoked in live mode")
        self.assertEqual(gh_args[:3], ["pr", "comment",
                         "https://github.com/cheshirecode/dotfiles/pull/124"])
        body = gh_args[gh_args.index("--body") + 1]
        self.assertIn("<!-- pr-cost:claude-session-fixture -->", body)

    def test_dry_mode_never_touches_gh(self):
        out, gh_args = self.run_with_stub_gh(live=False)
        self.assertFalse(out["commented"])
        self.assertIsNone(gh_args, f"gh was invoked in dry mode: {gh_args}")


if __name__ == "__main__":
    unittest.main()
