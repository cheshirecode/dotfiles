#!/usr/bin/env python3
"""The shared output contract of the per-harness usage scripts.

There are two usage scripts and they have drifted. `claude_session_usage.py`
emits cache_read_input_tokens, cache_creation_input_tokens, uncached_input_tokens
and unique_assistant_messages; `codex_session_usage.py` emits cached_input_tokens
and cwd instead. Neither knows about the other, and nothing had pinned the part
they share, so a consumer written against one lane could break silently against
the other.

The eight keys asserted here are the shared contract -- what any consumer may
rely on whatever harness produced the transcript:

    session_id  model  tokens_in  tokens_out
    window_start  window_end  path  usd_estimated

Every assertion parses JSON. None of them greps. `session_id` is a substring of
the `path` value that both scripts emit, so a grep for the key name passes
against a script that emits neither the key nor anything like it -- the
adjacent-match defect this repo keeps producing.

Each assertion below was proved red by mutating a scratch copy of the tree.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
CLAUDE_SCRIPT = SKILL_DIR / "scripts" / "claude_session_usage.py"
CODEX_SCRIPT = SKILL_DIR / "scripts" / "codex_session_usage.py"
COLLECT_SCRIPT = SKILL_DIR / "scripts" / "pr_cost_collect.py"

# The eight keys a consumer may rely on regardless of harness.
SHARED_KEYS = frozenset(
    {
        "session_id",
        "model",
        "tokens_in",
        "tokens_out",
        "window_start",
        "window_end",
        "path",
        "usd_estimated",
    }
)

# Documented default rates, in USD per million tokens. The two lanes DISAGREE on
# the output rate: claude_session_usage.py defaults to 25.0 and
# codex_session_usage.py to 30.0. That disagreement is real and is asserted as
# it stands -- each lane against its own declared default. Collapsing them to
# one number here would hide the drift rather than pin it.
CLAUDE_INPUT_RATE = 5.0
CLAUDE_OUTPUT_RATE = 25.0
CLAUDE_CACHE_READ_RATE = 0.5
CLAUDE_CACHE_WRITE_RATE = 6.25
CODEX_INPUT_RATE = 5.0
CODEX_OUTPUT_RATE = 30.0
CODEX_CACHE_READ_RATE = 0.5

# Deliberately non-round and mutually distinct, so no wrong pairing of the parts
# can coincidentally reproduce the right total.
CLAUDE_UNCACHED = 1_234_567
CLAUDE_CACHE_READ = 7_654_321
CLAUDE_CACHE_WRITE = 2_345_678
CLAUDE_OUTPUT = 987_654


def claude_event(message_id: str, usage: dict[str, int], timestamp: str) -> str:
    return json.dumps(
        {
            "sessionId": "usage-contract-session",
            "timestamp": timestamp,
            "message": {
                "role": "assistant",
                "id": message_id,
                "model": "claude-fixture-model",
                "usage": usage,
            },
        }
    )


def codex_token_count(usage: dict[str, int], timestamp: str) -> str:
    return json.dumps(
        {
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": {"type": "token_count", "info": {"total_token_usage": usage}},
        }
    )


class UsageKeyContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temporary_path = pathlib.Path(self.temporary_directory.name)

    def write_jsonl(self, name: str, lines: list[str]) -> pathlib.Path:
        path = self.temporary_path / name
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def run_usage(self, script: pathlib.Path, *arguments: str) -> dict:
        result = subprocess.run(
            [sys.executable, str(script), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"{script.name} exited {result.returncode}: {result.stderr.strip()}",
        )
        # A JSON parse, never a substring search: this is the assertion that a
        # grep-based version would pass while the keys were gone.
        return json.loads(result.stdout)

    def claude_usage(self, *, message_ids: list[str], usage: dict[str, int]) -> dict:
        lines = [
            claude_event(message_id, usage, f"2026-01-01T00:0{index}:00.000Z")
            for index, message_id in enumerate(message_ids)
        ]
        path = self.write_jsonl("claude-session.jsonl", lines)
        return self.run_usage(CLAUDE_SCRIPT, "--jsonl", str(path))

    def single_message_claude_usage(self) -> dict:
        return self.claude_usage(
            message_ids=["msg_contract_1"],
            usage={
                "input_tokens": CLAUDE_UNCACHED,
                "output_tokens": CLAUDE_OUTPUT,
                "cache_read_input_tokens": CLAUDE_CACHE_READ,
                "cache_creation_input_tokens": CLAUDE_CACHE_WRITE,
            },
        )

    def codex_usage(self, token_counts: list[dict[str, int]]) -> dict:
        lines = [
            json.dumps(
                {
                    "type": "session_meta",
                    "timestamp": "2026-01-01T00:00:00.000Z",
                    "payload": {
                        "session_id": "usage-contract-codex-session",
                        "cwd": "/fixture/cwd",
                        "model": "codex-fixture-model",
                        "timestamp": "2026-01-01T00:00:00.000Z",
                    },
                }
            )
        ]
        lines += [
            codex_token_count(usage, f"2026-01-01T00:1{index}:00.000Z")
            for index, usage in enumerate(token_counts)
        ]
        path = self.write_jsonl("codex-session.jsonl", lines)
        return self.run_usage(CODEX_SCRIPT, "--path", str(path))

    # 1. Both lanes emit the shared keys.

    def test_claude_emits_every_shared_key(self) -> None:
        data = self.single_message_claude_usage()
        self.assertEqual(
            SHARED_KEYS - data.keys(),
            set(),
            f"claude_session_usage.py is missing shared keys; it emitted {sorted(data)}",
        )

    def test_codex_emits_every_shared_key(self) -> None:
        data = self.codex_usage(
            [{"input_tokens": 4_444_444, "output_tokens": 555_555, "cached_input_tokens": 222_222}]
        )
        self.assertEqual(
            SHARED_KEYS - data.keys(),
            set(),
            f"codex_session_usage.py is missing shared keys; it emitted {sorted(data)}",
        )

    # 2. Claude arithmetic: tokens_in folds in both cache lanes.

    def test_claude_tokens_in_sums_uncached_and_both_cache_lanes(self) -> None:
        data = self.single_message_claude_usage()
        self.assertEqual(data["uncached_input_tokens"], CLAUDE_UNCACHED)
        self.assertEqual(data["cache_read_input_tokens"], CLAUDE_CACHE_READ)
        self.assertEqual(data["cache_creation_input_tokens"], CLAUDE_CACHE_WRITE)
        self.assertEqual(
            data["tokens_in"],
            CLAUDE_UNCACHED + CLAUDE_CACHE_READ + CLAUDE_CACHE_WRITE,
            "tokens_in must fold in cache read and cache write; a consumer that "
            "adds them itself would otherwise double-count",
        )
        self.assertEqual(data["tokens_out"], CLAUDE_OUTPUT)

    # 3. Claude de-duplicates by message id.

    def test_claude_counts_a_repeated_message_id_once(self) -> None:
        # msg_a appears twice. Counted once, tokens_in is 444_444; counted twice
        # it is 555_555. Two totals that cannot be confused for each other.
        first = {"input_tokens": 111_111, "output_tokens": 1_000}
        second = {"input_tokens": 333_333, "output_tokens": 2_000}
        lines = [
            claude_event("msg_a", first, "2026-01-01T00:00:00.000Z"),
            claude_event("msg_a", first, "2026-01-01T00:01:00.000Z"),
            claude_event("msg_b", second, "2026-01-01T00:02:00.000Z"),
        ]
        path = self.write_jsonl("claude-duplicate.jsonl", lines)
        data = self.run_usage(CLAUDE_SCRIPT, "--jsonl", str(path))
        self.assertEqual(
            data["unique_assistant_messages"],
            2,
            "three lines carry two distinct message ids",
        )
        self.assertEqual(
            data["tokens_in"],
            444_444,
            "a repeated message id was counted twice; 444444 is the deduplicated "
            "total and 555555 is the double-counted one",
        )
        self.assertEqual(data["tokens_out"], 3_000)

    # 4. Codex takes the LAST token_count event.

    def test_codex_takes_the_last_token_count_not_the_first_or_the_sum(self) -> None:
        # Three totals that are all distinguishable: first 1_000_000,
        # last 4_444_444, sum 5_444_444. Reading the first would be the
        # adjacent-match defect -- a plausible value from the wrong event.
        data = self.codex_usage(
            [
                {"input_tokens": 1_000_000, "output_tokens": 100_000, "cached_input_tokens": 10_000},
                {"input_tokens": 4_444_444, "output_tokens": 555_555, "cached_input_tokens": 222_222},
            ]
        )
        self.assertEqual(
            data["tokens_in"],
            4_444_444,
            "codex must report the last token_count event; 1000000 is the first "
            "event and 5444444 is the sum of both",
        )
        self.assertEqual(data["tokens_out"], 555_555)
        self.assertEqual(data["cached_input_tokens"], 222_222)
        self.assertEqual(
            data["window_end"],
            "2026-01-01T00:11:00.000Z",
            "window_end must come from the same event the totals came from",
        )

    # 5. usd_estimated is arithmetic on each lane's own documented defaults.

    def test_claude_usd_estimated_uses_its_documented_default_rates(self) -> None:
        data = self.single_message_claude_usage()
        expected = round(
            (
                CLAUDE_UNCACHED * CLAUDE_INPUT_RATE
                + CLAUDE_CACHE_READ * CLAUDE_CACHE_READ_RATE
                + CLAUDE_CACHE_WRITE * CLAUDE_CACHE_WRITE_RATE
                + CLAUDE_OUTPUT * CLAUDE_OUTPUT_RATE
            )
            / 1_000_000,
            4,
        )
        self.assertAlmostEqual(
            data["usd_estimated"],
            expected,
            places=4,
            msg=(
                "claude usd_estimated drifted from its documented defaults "
                f"({CLAUDE_INPUT_RATE}/{CLAUDE_OUTPUT_RATE}/"
                f"{CLAUDE_CACHE_READ_RATE}/{CLAUDE_CACHE_WRITE_RATE} per Mtok)"
            ),
        )

    def test_codex_usd_estimated_uses_its_documented_default_rates(self) -> None:
        tokens_in = 4_444_444
        tokens_out = 555_555
        cached = 222_222
        data = self.codex_usage(
            [{"input_tokens": tokens_in, "output_tokens": tokens_out, "cached_input_tokens": cached}]
        )
        # Cache-aware since the pr-cost-cache-tokens change: cached input is a
        # subset of input_tokens and is priced at the cache-read rate (0.5
        # default), not the 5.0 input rate.
        expected = round(
            (
                (tokens_in - cached) * CODEX_INPUT_RATE
                + cached * CODEX_CACHE_READ_RATE
                + tokens_out * CODEX_OUTPUT_RATE
            )
            / 1_000_000,
            4,
        )
        self.assertAlmostEqual(
            data["usd_estimated"],
            expected,
            places=4,
            msg=(
                "codex usd_estimated drifted from its documented defaults "
                f"({CODEX_INPUT_RATE}/{CODEX_OUTPUT_RATE}/{CODEX_CACHE_READ_RATE} per "
                "Mtok). Note this lane's output rate is 30.0 where claude's is 25.0."
            ),
        )


class DocumentedCollectorValuesTest(unittest.TestCase):
    """The two enum values SKILL.md's live-annotate recipe hardcodes.

    The recipe in SKILL.md passes `--harness claude` and
    `--confidence estimated` literally. Drop either value from the parser and
    argparse exits 2 with a choices error, so anyone following the documented
    recipe hits a wall the test suite never warned about. Nothing else pinned
    these two literals.

    Asserted by running the collector, not by reading its source. A source
    grep for `"claude"` matches HARNESSES, the harness guidance strings and
    the default-notes text, so it stays green after the choice is gone.
    """

    def emit(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(COLLECT_SCRIPT), "emit", *arguments],
            capture_output=True,
            text=True,
            check=False,
        )

    # Each test passes ONLY the flag it is about, so one removed choice fails
    # one test. A first version passed both flags in both tests, and then
    # either mutation failed both -- neither assertion isolated its own claim.
    # `--confidence` is optional, so the harness test can omit it; the
    # confidence test needs some harness and deliberately picks a different
    # one, so it survives `claude` being removed.

    def test_harness_claude_is_still_an_accepted_value(self) -> None:
        result = self.emit("--harness", "claude")
        self.assertEqual(
            result.returncode,
            0,
            "SKILL.md's recipe passes --harness claude: " f"{result.stderr.strip()}",
        )
        self.assertEqual(json.loads(result.stdout)["harness"], "claude")

    def test_confidence_estimated_is_still_an_accepted_value(self) -> None:
        result = self.emit("--harness", "codex", "--confidence", "estimated")
        self.assertEqual(
            result.returncode,
            0,
            "SKILL.md's recipe passes --confidence estimated: "
            f"{result.stderr.strip()}",
        )
        self.assertEqual(json.loads(result.stdout)["confidence"], "estimated")


if __name__ == "__main__":
    unittest.main()
