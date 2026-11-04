#!/usr/bin/env python3
"""Return a context action without changing task or host state."""

import argparse
import json


def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be nonnegative")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-units", type=nonnegative, required=True)
    parser.add_argument("--since-checkpoint", type=nonnegative, required=True)
    parser.add_argument("--context-pct", type=nonnegative)
    parser.add_argument("--role-switch", action="store_true")
    parser.add_argument("--read-truncated", action="store_true")
    args = parser.parse_args()
    if args.since_checkpoint > args.session_units:
        parser.error("since-checkpoint cannot exceed session-units")
    if args.context_pct is not None and args.context_pct > 100:
        parser.error("context-pct must be between 0 and 100")

    reasons = []
    if args.context_pct is not None and args.context_pct >= 50:
        reasons.append("measured-context")
    if args.session_units >= 8:
        reasons.append("session-unit-limit")
    if args.read_truncated:
        reasons.append("truncated-read")
    action = "handoff" if reasons else "continue"
    if action == "continue":
        if args.since_checkpoint >= 3:
            reasons.append("checkpoint-due")
        if args.role_switch:
            reasons.append("role-switch")
        if reasons:
            action = "checkpoint"
    print(json.dumps({
        "action": action,
        "reasons": reasons,
        "context_pct": args.context_pct,
        "context_source": "host-reported" if args.context_pct is not None else "unknown",
    }, sort_keys=True))
    return 0 if action == "continue" else 1


if __name__ == "__main__":
    raise SystemExit(main())
