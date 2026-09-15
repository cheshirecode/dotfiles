#!/usr/bin/env python3
"""Read the last Codex token_count event from a session JSONL."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import sys
from typing import Any

# USD per million tokens: (input, output, cache_read). Match exact names or
# dated snapshots only; newer variants must not inherit an older model rate.
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
    hits = [name for name in MODEL_RATES
            if lowered == name or re.fullmatch(re.escape(name) + r"-\d{4}-\d{2}-\d{2}", lowered)]
    return MODEL_RATES[max(hits, key=len)] if hits else None


def last_token_count(path: pathlib.Path) -> dict[str, Any]:
    session_id = None
    cwd = None
    window_start = None
    model = None
    observed_models: set[str] = set()
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
                session_id = payload.get("session_id") or payload.get("id") or session_id
                cwd = payload.get("cwd") or cwd
                window_start = payload.get("timestamp") or event.get("timestamp") or window_start
                model = payload.get("model") or model
            if event_type == "turn_context":
                model = payload.get("model") or model
            if event_type == "event_msg" and payload.get("type") == "token_count":
                info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
                usage = info.get("total_token_usage") if isinstance(info.get("total_token_usage"), dict) else {}
                if usage:
                    if usage != last_usage:
                        observed_models.add(model or "")
                    last_usage = usage
                    last_timestamp = event.get("timestamp")
    if last_usage is None:
        raise SystemExit(f"no token_count events in {path}")
    parts = input_parts(last_usage.get("input_tokens"), last_usage.get("cached_input_tokens"),
                        last_usage.get("cache_write_input_tokens"))
    return {
        "session_id": session_id,
        "cwd": cwd,
        "model": (next(iter(observed_models)) or None) if len(observed_models) == 1 else None,
        "tokens_in": last_usage.get("input_tokens"),
        "tokens_out": last_usage.get("output_tokens"),
        "cached_input_tokens": last_usage.get("cached_input_tokens"),
        "cache_write_input_tokens": last_usage.get("cache_write_input_tokens"),
        "uncached_input_tokens": parts[0] if parts else None,
        "window_start": window_start,
        "window_end": last_timestamp,
        "path": str(path),
    }


def latest_session(root: pathlib.Path) -> pathlib.Path:
    files = sorted(root.rglob("rollout-*.jsonl"))
    if not files:
        raise SystemExit(f"no rollout-*.jsonl under {root}")
    return files[-1]


def input_parts(total, cached, written):
    values = (total, cached if cached is not None else 0, written if written is not None else 0)
    if any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in values):
        return None
    total, cached, written = values
    if cached + written > total:
        return None
    return total - cached - written, cached, written


def estimate_usd(
    tokens_in: int | None,
    tokens_out: int | None,
    cached_in: int | None,
    input_rate: float | None,
    output_rate: float | None,
    cache_read_rate: float | None,
    cache_write_in: int | None = None,
    cache_write_rate: float | None = None,
) -> float | None:
    parts = input_parts(tokens_in, cached_in, cache_write_in)
    if parts is None or not isinstance(tokens_out, int) or isinstance(tokens_out, bool) or tokens_out < 0:
        return None
    uncached, cached, written = parts
    rates = (input_rate, output_rate, cache_read_rate)
    if any(rate is None for rate in rates) or (written and cache_write_rate is None):
        return None
    return round(
        (uncached * input_rate + cached * cache_read_rate
         + written * (cache_write_rate or 0) + tokens_out * output_rate) / 1_000_000,
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
    parser.add_argument("--cache-write-usd-per-mtok", type=float, default=None)
    args = parser.parse_args()
    explicit = (args.input_usd_per_mtok, args.output_usd_per_mtok,
                args.cache_read_usd_per_mtok, args.cache_write_usd_per_mtok)
    if any(rate is not None and (not math.isfinite(rate) or rate < 0) for rate in explicit):
        parser.error("rates must be finite and non-negative")
    path = args.path or latest_session(args.root)
    usage = last_token_count(path)

    table_rates = lookup_model_rates(usage.get("model"))
    defaults = table_rates or (None, None, None)
    input_rate, output_rate, cache_read_rate = (
        supplied if supplied is not None else fallback
        for supplied, fallback in zip(explicit[:3], defaults)
    )
    if any(rate is not None for rate in explicit):
        rate_source, usd_basis = "cli", "default-rates"
    elif table_rates is not None:
        rate_source, usd_basis = "model-table", "model-rates"
    else:
        rate_source, usd_basis = "unavailable", None

    usage["usd_estimated"] = estimate_usd(
        usage.get("tokens_in"),
        usage.get("tokens_out"),
        usage.get("cached_input_tokens"),
        input_rate,
        output_rate,
        cache_read_rate,
        usage.get("cache_write_input_tokens"),
        args.cache_write_usd_per_mtok,
    )
    usage["rate_source"] = rate_source
    usage["usd_basis"] = usd_basis if usage["usd_estimated"] is not None else None
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
