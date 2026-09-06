#!/usr/bin/env python3
"""Two ways a claude transcript yields no cost, and why they must differ.

Before the guard these produced byte-identical output — all zeros, model
null, usd_estimated 0.0, exit 0:

  empty         the session genuinely had no assistant turns
  format break  assistant turns exist, but `usage` is no longer a dict

The first is a true statement about a cheap session. The second is the
reader silently failing to understand its input, and reporting $0.0000 for
a session that may have cost real money. A transcript format change is
exactly how the second happens, and it would have surfaced nowhere.

The empty case stays quiet and zeroed on purpose. Making it loud too would
collapse the distinction again from the other side: the caller's doctor
classifies quiet-and-zeroed as `no-signal` and a non-zero exit as `broken`,
and those two words are the whole point.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[1]
READER = SKILL / "scripts" / "claude_session_usage.py"

SPEC = importlib.util.spec_from_file_location(
    "pr_cost_doctor", SKILL / "scripts" / "pr_cost_doctor.py"
)
doctor = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(doctor)


def user_line(session: str) -> dict:
    return {
        "type": "user",
        "sessionId": session,
        "timestamp": "2026-01-01T00:00:00Z",
        "message": {"role": "user", "content": "x"},
    }


def assistant_line(session: str, message_id: str, usage: object) -> dict:
    return {
        "type": "assistant",
        "sessionId": session,
        "timestamp": "2026-01-01T00:01:00Z",
        "message": {
            "role": "assistant",
            "id": message_id,
            "model": "claude-opus-5",
            "usage": usage,
        },
    }


GOOD_USAGE = {
    "input_tokens": 13,
    "output_tokens": 27,
    "cache_read_input_tokens": 101,
    "cache_creation_input_tokens": 59,
}


class ReaderFailureModeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = pathlib.Path(self._tmp.name)

    def transcript(self, name: str, events: list[dict]) -> pathlib.Path:
        path = self.tmp / f"{name}.jsonl"
        path.write_text(
            "".join(json.dumps(e) + "\n" for e in events), encoding="utf-8"
        )
        return path

    def run_reader(self, path: pathlib.Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(READER), "--jsonl", str(path)],
            capture_output=True,
            text=True,
        )

    def test_empty_session_is_quiet_and_zeroed(self) -> None:
        path = self.transcript("empty", [user_line("a")])
        proc = self.run_reader(path)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["assistant_messages_seen"], 0)
        self.assertEqual(payload["tokens_in"], 0)
        self.assertEqual(payload["tokens_out"], 0)

    def test_format_break_exits_non_zero(self) -> None:
        """Assistant turns with no readable usage must not price as zero."""
        path = self.transcript(
            "broken",
            [
                user_line("b"),
                # `usage` as a list is the shape change this guards against.
                assistant_line("b", "m1", [{"input_tokens": 900}]),
                assistant_line("b", "m2", [{"input_tokens": 700}]),
            ],
        )
        proc = self.run_reader(path)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("2 assistant message(s)", proc.stderr)
        self.assertNotIn("0.0", proc.stdout)

    def test_a_readable_message_alongside_unreadable_ones_is_not_a_break(self) -> None:
        """One good usage block means the format is understood. Do not fail."""
        path = self.transcript(
            "mixed",
            [
                user_line("c"),
                assistant_line("c", "m1", GOOD_USAGE),
                assistant_line("c", "m2", "not-a-dict"),
            ],
        )
        proc = self.run_reader(path)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["assistant_messages_seen"], 2)
        self.assertEqual(payload["unique_assistant_messages"], 1)
        self.assertEqual(payload["tokens_in"], 13 + 101 + 59)


class DoctorSeparatesTheCausesTest(unittest.TestCase):
    """The point of the guard: the doctor must give the two different words."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = pathlib.Path(self._tmp.name)

    def classify(self, name: str, events: list[dict]) -> str:
        path = self.tmp / f"{name}.jsonl"
        path.write_text(
            "".join(json.dumps(e) + "\n" for e in events), encoding="utf-8"
        )
        return doctor.run_reader(READER, "--jsonl", path)["status"]

    def test_empty_is_no_signal_and_format_break_is_broken(self) -> None:
        empty = self.classify("empty", [user_line("a")])
        broken = self.classify(
            "broken",
            [user_line("b"), assistant_line("b", "m1", [{"input_tokens": 900}])],
        )
        self.assertEqual(empty, "no-signal")
        self.assertEqual(broken, "broken")
        self.assertNotEqual(empty, broken)


if __name__ == "__main__":
    unittest.main()
