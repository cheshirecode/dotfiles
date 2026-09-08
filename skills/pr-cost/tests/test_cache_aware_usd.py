#!/usr/bin/env python3
"""Cache-aware USD estimation and per-model rate tables.

Two claims, both proved red against the unfixed readers:

1. The codex reader priced every input token -- cached ones included -- at the
   uncached rate. OpenAI semantics put cached tokens INSIDE input_tokens, so a
   session with a 50% cache hit rate was overestimated by the cached tokens
   times (input_rate - cache_read_rate). The claude reader never had this bug:
   it keeps cached tokens out of input_tokens and prices the split.

2. Neither reader used the model name it reports for anything. A gpt-5 session
   was billed at the lane's Sonnet-flavored default. The readers now carry a
   small prefix-matched rate table; explicit CLI flags still win.

The fixture model names ("claude-fixture-model", "codex-fixture-model") match
no table prefix on purpose: they pin the fallback, and every pre-existing
default-rates assertion stays green under them.
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


def claude_event(message_id: str, model: str, usage: dict[str, int]) -> str:
    return json.dumps(
        {
            "sessionId": "cache-aware-claude-session",
            "timestamp": "2026-01-01T00:00:00.000Z",
            "message": {
                "role": "assistant",
                "id": message_id,
                "model": model,
                "usage": usage,
            },
        }
    )


def codex_session(model: str, usage: dict[str, int]) -> str:
    meta = json.dumps(
        {
            "type": "session_meta",
            "timestamp": "2026-01-01T00:00:00.000Z",
            "payload": {
                "session_id": "cache-aware-codex-session",
                "cwd": "/fixture/cwd",
                "model": model,
                "timestamp": "2026-01-01T00:00:00.000Z",
            },
        }
    )
    count = json.dumps(
        {
            "type": "event_msg",
            "timestamp": "2026-01-01T00:01:00.000Z",
            "payload": {"type": "token_count", "info": {"total_token_usage": usage}},
        }
    )
    return meta + "\n" + count + "\n"


class CacheAwareUsdTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temporary_path = pathlib.Path(self.temporary_directory.name)

    def write_and_run(self, name: str, content: str, script: pathlib.Path, *extra: str) -> dict:
        path = self.temporary_path / name
        path.write_text(content, encoding="utf-8")
        flag = "--jsonl" if script is CLAUDE_SCRIPT else "--path"
        result = subprocess.run(
            [sys.executable, str(script), flag, str(path), *extra],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"{script.name} exited {result.returncode}: {result.stderr.strip()}",
        )
        return json.loads(result.stdout)

    # 1. Codex prices cached input at the cache-read rate, not the input rate.

    def test_codex_cached_tokens_are_priced_at_the_cache_rate(self) -> None:
        # Half the prompt was a cache hit. With input 5.0 / cache 0.5 / output
        # 30.0 the correct total is 28.8888; the old full-input pricing
        # produced 38.8888. The 10-dollar gap is the bug.
        data = self.write_and_run(
            "codex-cached.jsonl",
            codex_session(
                "codex-fixture-model",
                {
                    "input_tokens": 4_444_444,
                    "cached_input_tokens": 2_222_222,
                    "output_tokens": 555_555,
                },
            ),
            CODEX_SCRIPT,
        )
        expected = round(
            (
                (4_444_444 - 2_222_222) * 5.0
                + 2_222_222 * 0.5
                + 555_555 * 30.0
            )
            / 1_000_000,
            4,
        )
        self.assertAlmostEqual(
            data["usd_estimated"],
            expected,
            places=4,
            msg=(
                "cached input tokens were priced at the uncached rate; "
                f"expected {expected} with the 2,222,222 cached tokens at the "
                "cache-read rate"
            ),
        )

    def test_codex_uncached_input_tokens_excludes_cached(self) -> None:
        data = self.write_and_run(
            "codex-uncached.jsonl",
            codex_session(
                "codex-fixture-model",
                {"input_tokens": 4_444_444, "cached_input_tokens": 2_222_222, "output_tokens": 1},
            ),
            CODEX_SCRIPT,
        )
        self.assertEqual(data["uncached_input_tokens"], 2_222_222)

    # 2. The model table prices known models without CLI flags.

    def test_claude_sonnet_model_uses_sonnet_rates(self) -> None:
        # Sonnet rates 3.0 / 15.0 / 0.30 / 3.75. A 1M-token session with a
        # 1M-token cache read: 3.0 + 0.30 + 0.375 + 0.15 = 3.825. The old
        # flat defaults (5/25/0.5/6.25) priced the same session at 6.375.
        data = self.write_and_run(
            "claude-sonnet.jsonl",
            claude_event(
                "msg_1",
                "claude-sonnet-4-20250514",
                {
                    "input_tokens": 1_000_000,
                    "cache_read_input_tokens": 1_000_000,
                    "cache_creation_input_tokens": 100_000,
                    "output_tokens": 10_000,
                },
            ),
            CLAUDE_SCRIPT,
        )
        self.assertAlmostEqual(data["usd_estimated"], 3.825, places=4)

    def test_codex_gpt5_model_uses_gpt5_rates(self) -> None:
        # gpt-5 rates 1.25 / 10.0 / cache 0.125. 1M input with a 500k cache
        # hit and 100k output: 0.625 + 0.0625 + 1.0 = 1.6875.
        data = self.write_and_run(
            "codex-gpt5.jsonl",
            codex_session(
                "gpt-5-codex",
                {
                    "input_tokens": 1_000_000,
                    "cached_input_tokens": 500_000,
                    "output_tokens": 100_000,
                },
            ),
            CODEX_SCRIPT,
        )
        self.assertAlmostEqual(data["usd_estimated"], 1.6875, places=4)

    # 3. Explicit CLI flags still override the table.

    def test_explicit_flags_override_the_claude_model_table(self) -> None:
        data = self.write_and_run(
            "claude-override.jsonl",
            claude_event(
                "msg_1",
                "claude-sonnet-4-20250514",
                {
                    "input_tokens": 1_000_000,
                    "cache_read_input_tokens": 1_000_000,
                    "cache_creation_input_tokens": 100_000,
                    "output_tokens": 10_000,
                },
            ),
            CLAUDE_SCRIPT,
            "--input-usd-per-mtok", "5.0",
            "--output-usd-per-mtok", "25.0",
            "--cache-read-usd-per-mtok", "0.5",
            "--cache-write-usd-per-mtok", "6.25",
        )
        self.assertAlmostEqual(data["usd_estimated"], 6.375, places=4)

    # 4. The reader says which basis priced the session.

    def test_claude_reports_model_table_as_its_rate_source(self) -> None:
        data = self.write_and_run(
            "claude-source.jsonl",
            claude_event(
                "msg_1",
                "claude-sonnet-4-20250514",
                {"input_tokens": 1, "output_tokens": 1},
            ),
            CLAUDE_SCRIPT,
        )
        self.assertEqual(data["rate_source"], "model-table")
        self.assertEqual(data["usd_basis"], "model-rates")

    def test_claude_reports_defaults_for_an_unknown_model(self) -> None:
        data = self.write_and_run(
            "claude-fallback.jsonl",
            claude_event(
                "msg_1",
                "claude-fixture-model",
                {"input_tokens": 1, "output_tokens": 1},
            ),
            CLAUDE_SCRIPT,
        )
        self.assertEqual(data["rate_source"], "cli-default")
        self.assertEqual(data["usd_basis"], "default-rates")

    def test_codex_reports_model_table_as_its_rate_source(self) -> None:
        data = self.write_and_run(
            "codex-source.jsonl",
            codex_session(
                "gpt-5-codex",
                {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1},
            ),
            CODEX_SCRIPT,
        )
        self.assertEqual(data["rate_source"], "model-table")

    def test_codex_reports_defaults_for_an_unknown_model(self) -> None:
        data = self.write_and_run(
            "codex-fallback.jsonl",
            codex_session(
                "codex-fixture-model",
                {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1},
            ),
            CODEX_SCRIPT,
        )
        self.assertEqual(data["rate_source"], "cli-default")


if __name__ == "__main__":
    unittest.main()
