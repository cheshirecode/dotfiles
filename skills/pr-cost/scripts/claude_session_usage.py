#!/usr/bin/env python3
"""Sum unique assistant-message usage from a Claude Code session JSONL."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

# USD per million tokens: (input, output, cache_read, cache_write), matched by
# the longest prefix of the lowercased model name. Public Anthropic list
# prices; the claude lane reports input_tokens WITHOUT cache tokens, unlike
# the codex lane.
MODEL_RATES: dict[str, tuple[float, float, float, float]] = {
    "claude-opus-4": (15.0, 75.0, 1.5, 18.75),
    "claude-sonnet-4": (3.0, 15.0, 0.3, 3.75),
    "claude-haiku-4": (1.0, 5.0, 0.1, 1.25),
    "claude-3-7-sonnet": (3.0, 15.0, 0.3, 3.75),
    "claude-3-5-sonnet": (3.0, 15.0, 0.3, 3.75),
    "claude-3-5-haiku": (0.8, 4.0, 0.08, 1.0),
}


def lookup_model_rates(model: str | None) -> tuple[float, float, float, float] | None:
    if not model:
        return None
    lowered = model.lower()
    hits = [prefix for prefix in MODEL_RATES if lowered.startswith(prefix)]
    return MODEL_RATES[max(hits, key=len)] if hits else None


def session_usage(path: pathlib.Path) -> dict[str, Any]:
    messages: dict[str, dict[str, Any]] = {}
    assistant_seen = 0
    session_id = None
    model = None
    window_start = None
    window_end = None
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue
            session_id = event.get("sessionId") or session_id
            timestamp = event.get("timestamp")
            if isinstance(timestamp, str):
                window_start = window_start or timestamp
                window_end = timestamp
            message = event.get("message")
            if not isinstance(message, dict) or message.get("role") != "assistant":
                continue
            assistant_seen += 1
            message_id = message.get("id")
            usage = message.get("usage")
            if not isinstance(message_id, str) or not isinstance(usage, dict):
                continue
            messages[message_id] = usage
            if isinstance(message.get("model"), str):
                model = message["model"]

    # Assistant turns with no readable usage anywhere is a format change,
    # not a cheap session. Before this, both produced byte-identical output:
    # all zeros, model null, usd 0.0, exit 0. One is "nothing was said", the
    # other is "this reader no longer understands what it is reading", and
    # only the second is silent breakage. The empty case stays quiet and
    # zeroed on purpose; the caller's doctor classifies that as no-signal.
    if assistant_seen and not messages:
        raise SystemExit(
            f"{path}: {assistant_seen} assistant message(s), none carrying a "
            "readable usage block. The transcript format changed or this "
            "reader is out of date; a zero-cost estimate would be wrong "
            "rather than cheap."
        )

    tokens_in = 0
    tokens_out = 0
    cache_read = 0
    cache_write = 0
    for usage in messages.values():
        tokens_in += int(usage.get("input_tokens") or 0)
        tokens_out += int(usage.get("output_tokens") or 0)
        cache_read += int(usage.get("cache_read_input_tokens") or 0)
        cache_write += int(usage.get("cache_creation_input_tokens") or 0)

    return {
        "session_id": session_id,
        "model": model,
        "tokens_in": tokens_in + cache_read + cache_write,
        "tokens_out": tokens_out,
        "uncached_input_tokens": tokens_in,
        "cache_read_input_tokens": cache_read,
        "cache_creation_input_tokens": cache_write,
        "assistant_messages_seen": assistant_seen,
        "unique_assistant_messages": len(messages),
        "window_start": window_start,
        "window_end": window_end,
        "path": str(path),
    }


def estimate_usd(
    *,
    uncached: int,
    cache_read: int,
    cache_write: int,
    tokens_out: int,
    input_rate: float,
    output_rate: float,
    cache_read_rate: float,
    cache_write_rate: float,
) -> float:
    return round(
        (
            uncached * input_rate
            + cache_read * cache_read_rate
            + cache_write * cache_write_rate
            + tokens_out * output_rate
        )
        / 1_000_000,
        4,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jsonl", type=pathlib.Path, required=True)
    parser.add_argument("--input-usd-per-mtok", type=float, default=None)
    parser.add_argument("--output-usd-per-mtok", type=float, default=None)
    parser.add_argument("--cache-read-usd-per-mtok", type=float, default=None)
    parser.add_argument("--cache-write-usd-per-mtok", type=float, default=None)
    args = parser.parse_args()
    usage = session_usage(args.jsonl)

    table_rates = lookup_model_rates(usage.get("model"))
    explicit = (
        args.input_usd_per_mtok,
        args.output_usd_per_mtok,
        args.cache_read_usd_per_mtok,
        args.cache_write_usd_per_mtok,
    )
    if any(rate is not None for rate in explicit):
        input_rate = args.input_usd_per_mtok if args.input_usd_per_mtok is not None else 5.0
        output_rate = args.output_usd_per_mtok if args.output_usd_per_mtok is not None else 25.0
        cache_read_rate = (
            args.cache_read_usd_per_mtok if args.cache_read_usd_per_mtok is not None else 0.5
        )
        cache_write_rate = (
            args.cache_write_usd_per_mtok if args.cache_write_usd_per_mtok is not None else 6.25
        )
        rate_source, usd_basis = "cli", "default-rates"
    elif table_rates is not None:
        input_rate, output_rate, cache_read_rate, cache_write_rate = table_rates
        rate_source, usd_basis = "model-table", "model-rates"
    else:
        input_rate, output_rate, cache_read_rate, cache_write_rate = 5.0, 25.0, 0.5, 6.25
        rate_source, usd_basis = "cli-default", "default-rates"

    usage["usd_estimated"] = estimate_usd(
        uncached=int(usage["uncached_input_tokens"]),
        cache_read=int(usage["cache_read_input_tokens"]),
        cache_write=int(usage["cache_creation_input_tokens"]),
        tokens_out=int(usage["tokens_out"]),
        input_rate=input_rate,
        output_rate=output_rate,
        cache_read_rate=cache_read_rate,
        cache_write_rate=cache_write_rate,
    )
    usage["rate_source"] = rate_source
    usage["usd_basis"] = usd_basis
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
