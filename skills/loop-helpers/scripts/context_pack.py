#!/usr/bin/env python3
"""Emit a bounded, transcript-free loop handoff as one compact JSON object."""

from __future__ import annotations

import argparse
import json


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Build a compact loop handoff without parent-transcript text."
    )
    result.add_argument("--objective", required=True)
    result.add_argument("--known-evidence", action="append", required=True)
    result.add_argument("--constraints", action="append", required=True)
    result.add_argument("--budget", required=True)
    result.add_argument("--requested-return", required=True)
    result.add_argument("--recovery-handle", action="append", default=[])
    result.add_argument(
        "--max-bytes", type=int, default=8192,
        help="maximum serialized UTF-8 bytes, including newline (default: 8192)",
    )
    return result


def main() -> int:
    cli = parser()
    args = cli.parse_args()
    if args.max_bytes <= 0:
        cli.error("--max-bytes must be positive")
    pack = {
        "schema_version": 1,
        "objective": args.objective,
        "known_evidence": args.known_evidence,
        "constraints": args.constraints,
        "budget": args.budget,
        "requested_return": args.requested_return,
        "recovery_handles": args.recovery_handle,
    }
    payload = json.dumps(pack, separators=(",", ":"), sort_keys=True)
    size = len((payload + "\n").encode("utf-8"))
    if size > args.max_bytes:
        cli.error(
            f"context pack is {size} bytes; exceeds {args.max_bytes}-byte limit. "
            "Replace detailed evidence with artifact references or explicitly raise "
            "--max-bytes when the receiving context permits it; no fields were emitted."
        )
    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
