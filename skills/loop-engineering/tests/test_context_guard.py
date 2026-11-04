"""Exercise context boundaries through the actual stateless CLI."""

import json
from pathlib import Path
import subprocess
import sys
import unittest

GUARD = Path(__file__).resolve().parents[1] / "scripts/context_guard.py"


class ContextGuardTest(unittest.TestCase):
    def run_guard(self, units, since, *extra):
        return subprocess.run(
            [sys.executable, str(GUARD), "--session-units", str(units),
             "--since-checkpoint", str(since), *extra],
            capture_output=True, text=True,
        )

    def test_normal_work_with_unknown_meter(self):
        result = self.run_guard(2, 2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            "action": "continue", "reasons": [],
            "context_pct": None, "context_source": "unknown",
        })

    def test_checkpoint_due_at_three_units(self):
        result = self.run_guard(3, 3)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["action"], "checkpoint")

    def test_checkpoint_does_not_reset_session_limit(self):
        result = self.run_guard(8, 0)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["action"], "handoff")
        self.assertIn("session-unit-limit", json.loads(result.stdout)["reasons"])

    def test_measured_context_boundary(self):
        for percent, action, code in [(49, "continue", 0), (50, "handoff", 1)]:
            with self.subTest(percent=percent):
                result = self.run_guard(1, 1, "--context-pct", str(percent))
                self.assertEqual(result.returncode, code)
                self.assertEqual(json.loads(result.stdout)["action"], action)

    def test_role_change_requires_checkpoint(self):
        result = self.run_guard(1, 0, "--role-switch")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["action"], "checkpoint")

    def test_truncated_read_requires_handoff(self):
        result = self.run_guard(0, 0, "--read-truncated")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["action"], "handoff")

    def test_unknown_existing_history_requires_handoff(self):
        result = self.run_guard(0, 0, "--history-unknown")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["action"], "handoff")
        self.assertIn("unknown-history", json.loads(result.stdout)["reasons"])

    def test_invalid_observations_emit_no_decision(self):
        for units, since, extra in [(-1, 0, []), (1, 2, []),
                                    (1, 0, ["--context-pct", "101"]),
                                    (1, 0, ["--context-pct", "unknown"])]:
            with self.subTest(units=units, since=since, extra=extra):
                result = self.run_guard(units, since, *extra)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
