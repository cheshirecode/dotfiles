#!/usr/bin/env python3
"""Sum unique assistant-message usage from a Claude Code session JSONL."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any


def session_usage(path: pathlib.Path) -> dict[str, Any]:
    messages: dict[str, dict[str, Any]] = {}
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
            message_id = message.get("id")
            usage = message.get("usage")
            if not isinstance(message_id, str) or not isinstance(usage, dict):
                continue
            messages[message_id] = usage
            if isinstance(message.get("model"), str):
                model = message["model"]

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
    parser.add_argument("--input-usd-per-mtok", type=float, default=5.0)
    parser.add_argument("--output-usd-per-mtok", type=float, default=25.0)
    parser.add_argument("--cache-read-usd-per-mtok", type=float, default=0.5)
    parser.add_argument("--cache-write-usd-per-mtok", type=float, default=6.25)
    args = parser.parse_args()
    usage = session_usage(args.jsonl)
    usage["usd_estimated"] = estimate_usd(
        uncached=int(usage["uncached_input_tokens"]),
        cache_read=int(usage["cache_read_input_tokens"]),
        cache_write=int(usage["cache_creation_input_tokens"]),
        tokens_out=int(usage["tokens_out"]),
        input_rate=args.input_usd_per_mtok,
        output_rate=args.output_usd_per_mtok,
        cache_read_rate=args.cache_read_usd_per_mtok,
        cache_write_rate=args.cache_write_usd_per_mtok,
    )
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
