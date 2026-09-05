#!/usr/bin/env python3
"""Read the last Codex token_count event from a session JSONL."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any


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
        "window_start": window_start,
        "window_end": last_timestamp,
        "path": str(path),
    }


def latest_session(root: pathlib.Path) -> pathlib.Path:
    files = sorted(root.rglob("rollout-*.jsonl"))
    if not files:
        raise SystemExit(f"no rollout-*.jsonl under {root}")
    return files[-1]


def estimate_usd(tokens_in: int | None, tokens_out: int | None, input_rate: float, output_rate: float) -> float | None:
    if tokens_in is None or tokens_out is None:
        return None
    return round((tokens_in * input_rate + tokens_out * output_rate) / 1_000_000, 4)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", type=pathlib.Path, help="session JSONL; default = latest under --root")
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path.home() / ".codex" / "sessions",
        help="directory to search for rollout-*.jsonl",
    )
    parser.add_argument("--input-usd-per-mtok", type=float, default=5.0)
    parser.add_argument("--output-usd-per-mtok", type=float, default=30.0)
    args = parser.parse_args()
    path = args.path or latest_session(args.root)
    usage = last_token_count(path)
    usage["usd_estimated"] = estimate_usd(
        usage.get("tokens_in"),
        usage.get("tokens_out"),
        args.input_usd_per_mtok,
        args.output_usd_per_mtok,
    )
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
