#!/usr/bin/env python3
"""Require typed evidence coverage for every completion criterion."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile
from datetime import datetime, timezone
from typing import Any


SCHEMA_VERSION = 1
EVIDENCE_KINDS = {"command", "artifact", "git", "github", "url"}
CRITERION_ID = re.compile(r"^[a-z][a-z0-9_-]*$")


class GateError(ValueError):
    """Raised when an evidence-gate operation violates the contract."""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_criterion(value: str) -> tuple[str, str]:
    criterion_id, separator, description = value.partition("=")
    if not separator or not CRITERION_ID.fullmatch(criterion_id):
        raise GateError("criterion must use id=description with a lowercase identifier")
    if not description.strip():
        raise GateError(f"criterion description must not be empty: {criterion_id}")
    return criterion_id, description


def validate_gate(gate: dict[str, Any]) -> None:
    if gate.get("schema_version") != SCHEMA_VERSION:
        raise GateError(f"schema_version must be {SCHEMA_VERSION}")
    if not isinstance(gate.get("goal"), str) or not gate["goal"].strip():
        raise GateError("goal must be a non-empty string")
    criteria = gate.get("criteria")
    if not isinstance(criteria, dict) or not criteria:
        raise GateError("criteria must be a non-empty object")
    for criterion_id, criterion in criteria.items():
        if not CRITERION_ID.fullmatch(criterion_id):
            raise GateError(f"invalid criterion identifier: {criterion_id}")
        if not isinstance(criterion, dict):
            raise GateError(f"criterion must be an object: {criterion_id}")
        description = criterion.get("description")
        if not isinstance(description, str) or not description.strip():
            raise GateError(f"criterion description is empty: {criterion_id}")
        evidence = criterion.get("evidence")
        if not isinstance(evidence, list):
            raise GateError(f"criterion evidence must be a list: {criterion_id}")
        for record in evidence:
            validate_record(record, criterion_id)


def validate_record(record: Any, criterion_id: str) -> None:
    if not isinstance(record, dict):
        raise GateError(f"evidence record must be an object: {criterion_id}")
    if record.get("kind") not in EVIDENCE_KINDS:
        raise GateError(f"invalid evidence kind for {criterion_id}")
    for field in ("ref", "result", "recorded_at"):
        if not isinstance(record.get(field), str) or not record[field].strip():
            raise GateError(f"evidence {field} is empty for {criterion_id}")


def read_gate(path: pathlib.Path) -> dict[str, Any]:
    try:
        gate = json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise GateError(f"gate file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise GateError(f"gate file is not valid JSON: {path}: {exc}") from exc
    validate_gate(gate)
    return gate


def write_gate(path: pathlib.Path, gate: dict[str, Any]) -> None:
    validate_gate(gate)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(gate, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def command_init(args: argparse.Namespace) -> dict[str, Any]:
    if args.gate.exists() and not args.force:
        raise GateError(f"refusing to overwrite existing gate: {args.gate}")
    criteria: dict[str, dict[str, Any]] = {}
    for raw_criterion in args.criterion:
        criterion_id, description = parse_criterion(raw_criterion)
        if criterion_id in criteria:
            raise GateError(f"duplicate criterion: {criterion_id}")
        criteria[criterion_id] = {"description": description, "evidence": []}
    gate = {
        "schema_version": SCHEMA_VERSION,
        "goal": args.goal,
        "criteria": criteria,
    }
    write_gate(args.gate, gate)
    return gate


def command_record(args: argparse.Namespace) -> dict[str, Any]:
    gate = read_gate(args.gate)
    if args.criterion not in gate["criteria"]:
        raise GateError(f"unknown criterion: {args.criterion}")
    gate["criteria"][args.criterion]["evidence"].append(
        {
            "kind": args.kind,
            "ref": args.ref,
            "result": args.result,
            "recorded_at": now(),
        }
    )
    write_gate(args.gate, gate)
    return gate


def gate_report(path: pathlib.Path, gate: dict[str, Any]) -> dict[str, Any]:
    missing = [
        criterion_id
        for criterion_id, criterion in gate["criteria"].items()
        if not criterion["evidence"]
    ]
    covered = [
        criterion_id
        for criterion_id, criterion in gate["criteria"].items()
        if criterion["evidence"]
    ]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    status = "satisfied" if not missing else "unsatisfied"
    verification = (
        f"evidence-gate:{path.resolve()}#sha256={digest}" if not missing else ""
    )
    return {
        "status": status,
        "goal": gate["goal"],
        "covered": covered,
        "missing": missing,
        "verification": verification,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    initialize = subparsers.add_parser("init", help="declare completion criteria")
    initialize.add_argument("--gate", type=pathlib.Path, required=True)
    initialize.add_argument("--goal", required=True)
    initialize.add_argument(
        "--criterion",
        action="append",
        required=True,
        help="id=description; repeat for every observable goal clause",
    )
    initialize.add_argument("--force", action="store_true")
    initialize.set_defaults(handler=command_init)

    record = subparsers.add_parser("record", help="attach evidence to one criterion")
    record.add_argument("--gate", type=pathlib.Path, required=True)
    record.add_argument("--criterion", required=True)
    record.add_argument("--kind", choices=sorted(EVIDENCE_KINDS), required=True)
    record.add_argument("--ref", required=True)
    record.add_argument("--result", required=True)
    record.set_defaults(handler=command_record)

    check = subparsers.add_parser("check", help="require evidence for all criteria")
    check.add_argument("--gate", type=pathlib.Path, required=True)
    check.add_argument(
        "--quiet",
        action="store_true",
        help="emit one index line instead of the full document",
    )
    check.set_defaults(handler=lambda args: read_gate(args.gate))

    show = subparsers.add_parser("show", help="render the full gate")
    show.add_argument("--gate", type=pathlib.Path, required=True)
    show.add_argument(
        "--quiet",
        action="store_true",
        help="emit one index line instead of the full document",
    )
    show.set_defaults(handler=lambda args: read_gate(args.gate))
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        gate = args.handler(args)
        if args.command == "check":
            report = gate_report(args.gate, gate)
            if getattr(args, "quiet", False):
                # The index, not the log: the caller acts on status and the
                # count, and pipes the rest to /dev/null anyway.
                covered = len(report["covered"])
                total = covered + len(report["missing"])
                line = f"{report['status']} {covered}/{total}"
                if report["missing"]:
                    line += " — missing: " + ", ".join(report["missing"][:5])
                print(line)
            else:
                print(json.dumps(report, indent=2, sort_keys=True))
            return 0 if report["status"] == "satisfied" else 1
        if getattr(args, "quiet", False):
            print(f"{len(gate['criteria'])} criteria — {gate.get('goal','')}")
        else:
            print(json.dumps(gate, indent=2, sort_keys=True))
        return 0
    except GateError as exc:
        print(f"evidence-gate: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
