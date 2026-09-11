#!/usr/bin/env python3
"""Sum unique assistant-message usage from a Claude Code session JSONL."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any, NamedTuple


class Rates(NamedTuple):
    """USD per million tokens for one model family."""

    input: float
    output: float
    cache_read: float
    cache_write_5m: float
    cache_write_1h: float


def _rates(input_rate: float, output_rate: float, *, cache_read: float | None = None) -> Rates:
    """Derive the cache rates from Anthropic's published multipliers.

    Reads cost 0.1x input; writes cost 1.25x for the 5-minute TTL and 2x for
    the 1-hour TTL. Stating the multipliers once keeps a hand-typed write rate
    from drifting away from its input rate -- and the 1-hour rate is the one
    that matters here, because Claude Code sessions run the 1-hour TTL.
    `cache_read` is passed only for a model that departs from the 0.1x rule.
    """
    return Rates(
        input=input_rate,
        output=output_rate,
        cache_read=input_rate * 0.1 if cache_read is None else cache_read,
        cache_write_5m=input_rate * 1.25,
        cache_write_1h=input_rate * 2.0,
    )


# Matched by the longest prefix of the lowercased model name. Public Anthropic
# list prices; the claude lane reports input_tokens WITHOUT cache tokens,
# unlike the codex lane.
#
# The 4-6/4-7/4-8 rows are not redundant with "claude-opus-4". Opus 4.6 and
# later are priced like Opus 5 (5/25), not like Opus 4.0 (15/75), so the bare
# prefix swallowed them and overcharged by 3x -- a plausible number rather
# than an error. Longest-prefix matching keeps 4.0/4.1 on the 15/75 row.
MODEL_RATES: dict[str, Rates] = {
    "claude-fable-5-1": _rates(10.0, 50.0, cache_read=0.25),
    "claude-fable-5": _rates(10.0, 50.0),
    "claude-opus-5": _rates(5.0, 25.0),
    "claude-opus-4-8": _rates(5.0, 25.0),
    "claude-opus-4-7": _rates(5.0, 25.0),
    "claude-opus-4-6": _rates(5.0, 25.0),
    "claude-opus-4": _rates(15.0, 75.0),
    "claude-sonnet-5": _rates(2.0, 10.0),
    "claude-sonnet-4": _rates(3.0, 15.0),
    "claude-haiku-4": _rates(1.0, 5.0),
    "claude-3-7-sonnet": _rates(3.0, 15.0),
    "claude-3-5-sonnet": _rates(3.0, 15.0),
    "claude-3-5-haiku": _rates(0.8, 4.0),
}


def lookup_model_rates(model: str | None) -> Rates | None:
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
    cache_write_5m = 0
    cache_write_1h = 0
    for usage in messages.values():
        tokens_in += int(usage.get("input_tokens") or 0)
        tokens_out += int(usage.get("output_tokens") or 0)
        cache_read += int(usage.get("cache_read_input_tokens") or 0)
        written = int(usage.get("cache_creation_input_tokens") or 0)
        cache_write += written
        # usage.cache_creation says which TTL each write bought; the flat
        # cache_creation_input_tokens total does not. Claude Code sessions run
        # the 1-hour TTL, which costs 2x input rather than 1.25x, so pricing
        # every write at 1.25x undercharges systematically.
        breakdown = usage.get("cache_creation") or {}
        write_5m = int(breakdown.get("ephemeral_5m_input_tokens") or 0)
        write_1h = int(breakdown.get("ephemeral_1h_input_tokens") or 0)
        if write_5m or write_1h:
            cache_write_5m += write_5m
            cache_write_1h += write_1h
        else:
            # Transcripts predating cache_creation carry no breakdown. Bill
            # those at the cheaper 5-minute rate so a missing split
            # understates rather than inflates, and the two split fields
            # still sum to cache_creation_input_tokens.
            cache_write_5m += written

    return {
        "session_id": session_id,
        "model": model,
        "tokens_in": tokens_in + cache_read + cache_write,
        "tokens_out": tokens_out,
        "uncached_input_tokens": tokens_in,
        "cache_read_input_tokens": cache_read,
        "cache_creation_input_tokens": cache_write,
        "cache_write_5m_input_tokens": cache_write_5m,
        "cache_write_1h_input_tokens": cache_write_1h,
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
    cache_write_5m: int,
    cache_write_1h: int,
    tokens_out: int,
    input_rate: float,
    output_rate: float,
    cache_read_rate: float,
    cache_write_5m_rate: float,
    cache_write_1h_rate: float,
) -> float:
    return round(
        (
            uncached * input_rate
            + cache_read * cache_read_rate
            + cache_write_5m * cache_write_5m_rate
            + cache_write_1h * cache_write_1h_rate
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
        # An explicit write rate is a blunt override: it applies to both TTLs,
        # because the caller asked for one number.
        cache_write_5m_rate = cache_write_1h_rate = (
            args.cache_write_usd_per_mtok if args.cache_write_usd_per_mtok is not None else 6.25
        )
        rate_source, usd_basis = "cli", "default-rates"
    elif table_rates is not None:
        input_rate = table_rates.input
        output_rate = table_rates.output
        cache_read_rate = table_rates.cache_read
        cache_write_5m_rate = table_rates.cache_write_5m
        cache_write_1h_rate = table_rates.cache_write_1h
        rate_source, usd_basis = "model-table", "model-rates"
    else:
        input_rate, output_rate, cache_read_rate = 5.0, 25.0, 0.5
        cache_write_5m_rate = cache_write_1h_rate = 6.25
        rate_source, usd_basis = "cli-default", "default-rates"

    usage["usd_estimated"] = estimate_usd(
        uncached=int(usage["uncached_input_tokens"]),
        cache_read=int(usage["cache_read_input_tokens"]),
        cache_write_5m=int(usage["cache_write_5m_input_tokens"]),
        cache_write_1h=int(usage["cache_write_1h_input_tokens"]),
        tokens_out=int(usage["tokens_out"]),
        input_rate=input_rate,
        output_rate=output_rate,
        cache_read_rate=cache_read_rate,
        cache_write_5m_rate=cache_write_5m_rate,
        cache_write_1h_rate=cache_write_1h_rate,
    )
    usage["rate_source"] = rate_source
    usage["usd_basis"] = usd_basis
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
