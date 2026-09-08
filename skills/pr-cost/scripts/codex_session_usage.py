#!/usr/bin/env python3
"""Read the last Codex token_count event from a session JSONL."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

# USD per million tokens: (input, output, cache_read), matched by the longest
# prefix of the lowercased model name. OpenAI prices cached input as a subset
# of input_tokens, so the reader subtracts it before pricing.
MODEL_RATES: dict[str, tuple[float, float, float]] = {
    "gpt-5-codex": (1.25, 10.0, 0.125),
    "gpt-5": (1.25, 10.0, 0.125),
    "gpt-4.1": (2.0, 8.0, 0.5),
    "gpt-4o": (2.5, 10.0, 1.25),
    "o3": (2.0, 8.0, 0.5),
    "o4-mini": (1.1, 4.4, 0.275),
    "codex-mini": (1.5, 6.0, 0.375),
}


def lookup_model_rates(model: str | None) -> tuple[float, float, float] | None:
    if not model:
        return None
    lowered = model.lower()
    hits = [prefix for prefix in MODEL_RATES if lowered.startswith(prefix)]
    return MODEL_RATES[max(hits, key=len)] if hits else None


def last_token_count(path: pathlib.Path) -> dict[str, Any]:
    session_id = None
    cwd = None
    window_start = None
    model = None
    last_usage: dict[str, Any] | None = None
    last_timestamp = None
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            payload = event.get("payload") if isinstance(event, dict) else None
            if not isinstance(payload, dict):
                continue
            event_type = event.get("type")
            if event_type == "session_meta":
                session_id = payload.get("session_id") or session_id
                cwd = payload.get("cwd") or cwd
                window_start = payload.get("timestamp") or event.get("timestamp") or window_start
                model = payload.get("model") or payload.get("model_provider") or model
            if event_type == "event_msg" and payload.get("type") == "token_count":
                info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
                usage = info.get("total_token_usage") if isinstance(info.get("total_token_usage"), dict) else {}
                if usage:
                    last_usage = usage
                    last_timestamp = event.get("timestamp")
    if last_usage is None:
        raise SystemExit(f"no token_count events in {path}")
    return {
        "session_id": session_id,
        "cwd": cwd,
        "model": model,
        "tokens_in": last_usage.get("input_tokens"),
        "tokens_out": last_usage.get("output_tokens"),
        "cached_input_tokens": last_usage.get("cached_input_tokens"),
        "cache_write_input_tokens": last_usage.get("cache_write_input_tokens"),
        "uncached_input_tokens": (
            max((last_usage.get("input_tokens") or 0) - (last_usage.get("cached_input_tokens") or 0), 0)
            if last_usage.get("input_tokens") is not None
            else None
        ),
        "window_start": window_start,
        "window_end": last_timestamp,
        "path": str(path),
    }


def latest_session(root: pathlib.Path) -> pathlib.Path:
    files = sorted(root.rglob("rollout-*.jsonl"))
    if not files:
        raise SystemExit(f"no rollout-*.jsonl under {root}")
    return files[-1]


def estimate_usd(
    tokens_in: int | None,
    tokens_out: int | None,
    cached_in: int | None,
    input_rate: float,
    output_rate: float,
    cache_read_rate: float,
) -> float | None:
    if tokens_in is None or tokens_out is None:
        return None
    # cached_input_tokens is a subset of input_tokens in the OpenAI usage
    # shape, so price the remainder at the input rate and the cached share at
    # the cache-read rate.
    cached = min(max(cached_in or 0, 0), tokens_in)
    uncached = tokens_in - cached
    return round(
        (uncached * input_rate + cached * cache_read_rate + tokens_out * output_rate) / 1_000_000,
        4,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", type=pathlib.Path, help="session JSONL; default = latest under --root")
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path.home() / ".codex" / "sessions",
        help="directory to search for rollout-*.jsonl",
    )
    parser.add_argument("--input-usd-per-mtok", type=float, default=None)
    parser.add_argument("--output-usd-per-mtok", type=float, default=None)
    parser.add_argument("--cache-read-usd-per-mtok", type=float, default=None)
    args = parser.parse_args()
    path = args.path or latest_session(args.root)
    usage = last_token_count(path)

    table_rates = lookup_model_rates(usage.get("model"))
    explicit = (args.input_usd_per_mtok, args.output_usd_per_mtok, args.cache_read_usd_per_mtok)
    if any(rate is not None for rate in explicit):
        input_rate = args.input_usd_per_mtok if args.input_usd_per_mtok is not None else 5.0
        output_rate = args.output_usd_per_mtok if args.output_usd_per_mtok is not None else 30.0
        cache_read_rate = args.cache_read_usd_per_mtok if args.cache_read_usd_per_mtok is not None else 0.5
        rate_source, usd_basis = "cli", "default-rates"
    elif table_rates is not None:
        input_rate, output_rate, cache_read_rate = table_rates
        rate_source, usd_basis = "model-table", "model-rates"
    else:
        input_rate, output_rate, cache_read_rate = 5.0, 30.0, 0.5
        rate_source, usd_basis = "cli-default", "default-rates"

    usage["usd_estimated"] = estimate_usd(
        usage.get("tokens_in"),
        usage.get("tokens_out"),
        usage.get("cached_input_tokens"),
        input_rate,
        output_rate,
        cache_read_rate,
    )
    usage["rate_source"] = rate_source
    usage["usd_basis"] = usd_basis
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
