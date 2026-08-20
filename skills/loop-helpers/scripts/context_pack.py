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
    return result


def main() -> int:
    args = parser().parse_args()
    pack = {
        "schema_version": 1,
        "objective": args.objective,
        "known_evidence": args.known_evidence,
        "constraints": args.constraints,
        "budget": args.budget,
        "requested_return": args.requested_return,
        "recovery_handles": args.recovery_handle,
    }
    print(json.dumps(pack, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
