#!/usr/bin/env python3
"""The opencode lane: SQLite input, and a cost the provider actually billed.

opencode differs from the other two harnesses in two ways that a consumer
can get wrong:

  * its session store is a SQLite database, not a JSONL transcript
  * it records the provider's own `cost`, so its USD is billed rather than
    inferred from a rate table

The second is the one worth pinning. If this lane's `usd_basis` ever silently
became `default-rates`, a real billed figure would start reading as a guess,
and nothing else in the suite would notice.

The token invariant is checked against the shape observed in real rows:
`input` excludes cache, and input + output + reasoning + cache.read +
cache.write equals the `total` opencode records.
"""

from __future__ import annotations

import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest

SKILL = pathlib.Path(__file__).resolve().parents[1]
READER = SKILL / "scripts" / "opencode_session_usage.py"

# Distinct, non-round, and mutually unequal so no wrong pairing of the parts
# reproduces a right-looking total.
TOKENS = {
    "input": 1_234_567,
    "output": 987_654,
    "reasoning": 4_321,
    "cache": {"read": 7_654_321, "write": 2_345_678},
}
COST = 12.345678


def build_db(path: pathlib.Path, messages: list[dict], directory: str = "/repo") -> None:
    conn = sqlite3.connect(path)
    try:
        conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT)")
        conn.execute(
            "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, "
            "time_created INTEGER, data TEXT)"
        )
        conn.execute("INSERT INTO session VALUES ('ses_1', ?)", (directory,))
        for index, data in enumerate(messages):
            conn.execute(
                "INSERT INTO message VALUES (?, 'ses_1', ?, ?)",
                (f"m{index}", 1_767_225_600_000 + index * 1000, json.dumps(data)),
            )
        conn.commit()
    finally:
        conn.close()


def assistant(tokens: object, cost: float = COST) -> dict:
    message = {
        "role": "assistant",
        "modelID": "some/model",
        "providerID": "some-provider",
        "cost": cost,
    }
    if tokens is not None:
        message["tokens"] = tokens
    return message


class OpencodeReaderTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = pathlib.Path(self._tmp.name)

    def read(self, messages: list[dict], *args: str) -> subprocess.CompletedProcess:
        db = self.tmp / "opencode.db"
        if db.exists():
            db.unlink()
        build_db(db, messages)
        return subprocess.run(
            [sys.executable, str(READER), "--db", str(db), *args],
            capture_output=True,
            text=True,
        )

    def payload(self, messages: list[dict], *args: str) -> dict:
        proc = self.read(messages, *args)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def test_usd_comes_from_the_provider_not_a_rate_table(self) -> None:
        payload = self.payload([assistant(TOKENS)])
        self.assertEqual(payload["usd_basis"], "provider-reported")
        self.assertAlmostEqual(payload["usd_estimated"], COST, places=6)

    def test_cost_is_summed_across_messages(self) -> None:
        payload = self.payload([assistant(TOKENS, 1.5), assistant(TOKENS, 2.25)])
        self.assertAlmostEqual(payload["usd_estimated"], 3.75, places=6)

    def test_token_split_matches_opencodes_own_total(self) -> None:
        payload = self.payload([assistant(TOKENS)])
        total = (
            TOKENS["input"]
            + TOKENS["output"]
            + TOKENS["reasoning"]
            + TOKENS["cache"]["read"]
            + TOKENS["cache"]["write"]
        )
        self.assertEqual(payload["tokens_in"] + payload["tokens_out"], total)
        self.assertEqual(
            payload["tokens_in"],
            TOKENS["input"] + TOKENS["cache"]["read"] + TOKENS["cache"]["write"],
        )
        self.assertEqual(
            payload["tokens_out"], TOKENS["output"] + TOKENS["reasoning"]
        )

    def test_reasoning_is_counted_as_output_not_dropped(self) -> None:
        """Reasoning tokens are generated and billed; losing them understates cost."""
        payload = self.payload([assistant(TOKENS)])
        self.assertEqual(payload["reasoning_tokens"], TOKENS["reasoning"])
        self.assertGreater(payload["tokens_out"], TOKENS["output"])

    def test_schema_change_exits_non_zero(self) -> None:
        """Assistant turns with no readable token object must not price as zero."""
        proc = self.read([assistant(None), assistant(None)])
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("2 assistant message(s)", proc.stderr)

    def test_an_unbilled_turn_alongside_a_billed_one_is_not_a_schema_change(self) -> None:
        payload = self.payload([assistant(TOKENS), assistant(None)])
        self.assertEqual(payload["assistant_messages_seen"], 2)
        self.assertEqual(payload["unique_assistant_messages"], 1)

    def test_cwd_filter_rejects_a_directory_with_no_sessions(self) -> None:
        proc = self.read([assistant(TOKENS)], "--cwd", "/not/this/repo")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no opencode session", proc.stderr)

    def test_missing_database_is_reported_not_crashed(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(READER), "--db", str(self.tmp / "absent.db")],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no opencode database", proc.stderr)


if __name__ == "__main__":
    unittest.main()
