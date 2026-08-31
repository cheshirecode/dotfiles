#!/usr/bin/env python3
"""Manage the deterministic state boundary of a bounded agent loop."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sys
import tempfile
from collections.abc import Callable, Iterator
from contextlib import ExitStack, contextmanager
from datetime import datetime, timezone
from functools import wraps
from typing import Any


SCHEMA_VERSION = 1
TERMINAL_STATUSES = {
    "complete",
    "blocked",
    "needs_human",
    "budget_exhausted",
    "cancelled",
    "continue_scheduled",
}
RESUMABLE_STATUSES = {
    "blocked",
    "needs_human",
    "budget_exhausted",
    "continue_scheduled",
}
NON_RESUMABLE_STATUSES = TERMINAL_STATUSES - RESUMABLE_STATUSES
ALL_STATUSES = {"running", *TERMINAL_STATUSES}


class StateError(ValueError):
    """Raised when a requested transition violates the loop contract."""


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_state_snapshot(path: pathlib.Path) -> tuple[dict[str, Any], bytes]:
    try:
        raw_state = path.read_bytes()
    except FileNotFoundError as exc:
        raise StateError(f"state file does not exist: {path}") from exc
    except OSError as exc:
        raise StateError(f"state file is not readable: {path}: {exc}") from exc
    try:
        state = json.loads(raw_state)
    except json.JSONDecodeError as exc:
        raise StateError(f"state file is not valid JSON: {path}: {exc}") from exc
    validate_state(state)
    return state, raw_state


def read_state(path: pathlib.Path) -> dict[str, Any]:
    return read_state_snapshot(path)[0]


@contextmanager
def state_lock(path: pathlib.Path) -> Iterator[None]:
    """Serialize mutations of one state path across agent processes."""
    resolved_path = path.resolve(strict=False)
    resolved_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = resolved_path.with_name(f".{resolved_path.name}.lock")
    handle = lock_path.open("a+b")
    locked = False
    try:
        if os.name == "nt":
            import msvcrt

            handle.seek(0, os.SEEK_END)
            if handle.tell() == 0:
                handle.write(b"\0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        locked = True
        yield
    finally:
        if locked and os.name == "nt":
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        elif locked:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


@contextmanager
def state_locks(*paths: pathlib.Path) -> Iterator[None]:
    """Acquire multiple state locks in stable order to avoid deadlocks."""
    ordered_paths = sorted(
        {path.resolve(strict=False) for path in paths},
        key=lambda path: str(path),
    )
    with ExitStack() as stack:
        for path in ordered_paths:
            stack.enter_context(state_lock(path))
        yield


def serialized_state_paths(
    *attribute_names: str,
) -> Callable[
    [Callable[[argparse.Namespace], dict[str, Any]]],
    Callable[[argparse.Namespace], dict[str, Any]],
]:
    """Lock argparse path attributes for the duration of a state transition."""

    def decorate(
        handler: Callable[[argparse.Namespace], dict[str, Any]],
    ) -> Callable[[argparse.Namespace], dict[str, Any]]:
        @wraps(handler)
        def locked_handler(args: argparse.Namespace) -> dict[str, Any]:
            with state_locks(*(getattr(args, name) for name in attribute_names)):
                return handler(args)

        return locked_handler

    return decorate


def write_state_unlocked(
    path: pathlib.Path,
    state: dict[str, Any],
    *,
    expect_sha256: str | None = None,
) -> None:
    validate_state(state)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temporary_path = pathlib.Path(temporary_name)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if expect_sha256 is not None:
            try:
                actual_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
            except FileNotFoundError as exc:
                raise StateError("state disappeared before guarded write") from exc
            if actual_sha256 != expect_sha256:
                raise StateError(
                    "state fingerprint changed during guarded write; refusing write"
                )
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def validate_state(state: dict[str, Any]) -> None:
    if not isinstance(state, dict):
        raise StateError("state must be a JSON object")
    if state.get("schema_version") != SCHEMA_VERSION:
        raise StateError(f"schema_version must be {SCHEMA_VERSION}")
    for field in ("goal", "next_action", "terminal_status"):
        if not isinstance(state.get(field), str):
            raise StateError(f"{field} must be a string")
    if not state["goal"].strip():
        raise StateError("goal must not be empty")
    if state["terminal_status"] not in ALL_STATUSES:
        raise StateError(f"invalid terminal_status: {state['terminal_status']}")

    evidence = state.get("progress_evidence")
    if not isinstance(evidence, list) or not evidence:
        raise StateError("progress_evidence must be a non-empty list")
    if not all(isinstance(item, str) and item.strip() for item in evidence):
        raise StateError("progress_evidence entries must be non-empty strings")

    budget = state.get("budget")
    if not isinstance(budget, dict):
        raise StateError("budget must be an object")
    if not isinstance(budget.get("unit"), str) or not budget["unit"].strip():
        raise StateError("budget.unit must be a non-empty string")
    limit = budget.get("limit")
    used = budget.get("used")
    if not isinstance(limit, int) or limit < 1:
        raise StateError("budget.limit must be a positive integer")
    if not isinstance(used, int) or used < 0 or used > limit:
        raise StateError("budget.used must be between zero and budget.limit")

    if state["terminal_status"] == "running" and used >= limit:
        raise StateError("running state cannot have an exhausted budget")
    verification = state.get("verification")
    if state["terminal_status"] == "complete" and (
        not isinstance(verification, str) or not verification.strip()
    ):
        raise StateError("complete state requires non-empty verification")
    if not isinstance(state.get("history"), list):
        raise StateError("history must be a list")


def require_running(state: dict[str, Any]) -> None:
    if state["terminal_status"] != "running":
        raise StateError(
            f"cannot transition terminal state: {state['terminal_status']}"
        )


def append_history(
    state: dict[str, Any],
    event: str,
    evidence: list[str],
    next_action: str,
) -> None:
    state["history"].append(
        {
            "at": now(),
            "event": event,
            "evidence": evidence,
            "next_action": next_action,
        }
    )


@serialized_state_paths("state")
def command_init(args: argparse.Namespace) -> dict[str, Any]:
    if args.state.exists() and not args.force:
        raise StateError(f"refusing to overwrite existing state: {args.state}")
    state: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "goal": args.goal,
        "progress_evidence": args.evidence,
        "budget": {
            "unit": args.budget_unit,
            "limit": args.budget_limit,
            "used": 0,
        },
        "next_action": args.next_action,
        "terminal_status": "running",
        "allowed_effects": args.allowed_effect,
        "approval_boundary": args.approval_boundary,
        "verification": "",
        "history": [],
    }
    append_history(state, "initialized", args.evidence, args.next_action)
    write_state_unlocked(args.state, state)
    return state


@serialized_state_paths("state")
def command_advance(args: argparse.Namespace) -> dict[str, Any]:
    state, raw_state = read_state_snapshot(args.state)
    expect_sha256 = hashlib.sha256(raw_state).hexdigest()
    require_running(state)
    consume_budget(state, args.consume)
    state["progress_evidence"].extend(args.evidence)
    state["next_action"] = args.next_action
    if state["budget"]["used"] == state["budget"]["limit"]:
        state["terminal_status"] = "budget_exhausted"
    append_history(state, "advanced", args.evidence, args.next_action)
    write_state_unlocked(args.state, state, expect_sha256=expect_sha256)
    return state


def consume_budget(state: dict[str, Any], amount: int) -> None:
    remaining = state["budget"]["limit"] - state["budget"]["used"]
    if amount > remaining:
        raise StateError(
            f"transition consumes {amount} {state['budget']['unit']}; "
            f"only {remaining} remain"
        )
    state["budget"]["used"] += amount


@serialized_state_paths("state", "new_state")
def command_resume(args: argparse.Namespace) -> dict[str, Any]:
    if args.state.resolve() == args.new_state.resolve():
        raise StateError("resume requires a distinct --new-state path")
    if args.new_state.exists():
        raise StateError(f"refusing to overwrite existing state: {args.new_state}")
    predecessor, raw_predecessor = read_state_snapshot(args.state)
    status = predecessor["terminal_status"]
    if status not in RESUMABLE_STATUSES:
        raise StateError(f"cannot resume state with status: {status}")
    if (
        status == "budget_exhausted"
        or predecessor["budget"]["used"] == predecessor["budget"]["limit"]
    ) and args.extend_budget == 0:
        raise StateError(
            "resume requires --extend-budget when predecessor budget is exhausted"
        )

    digest = hashlib.sha256(raw_predecessor).hexdigest()
    predecessor_reference = {
        "path": str(args.state.resolve()),
        "sha256": digest,
        "terminal_status": status,
    }
    resume_evidence = [
        (f"Resumed from {predecessor_reference['path']} ({status}, sha256={digest})"),
        *args.evidence,
    ]
    state: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "goal": predecessor["goal"],
        "progress_evidence": resume_evidence,
        "budget": {
            "unit": predecessor["budget"]["unit"],
            "limit": predecessor["budget"]["limit"] + args.extend_budget,
            "used": predecessor["budget"]["used"],
        },
        "next_action": args.next_action,
        "terminal_status": "running",
        "allowed_effects": [
            *predecessor.get("allowed_effects", []),
            *args.allowed_effect,
        ],
        "approval_boundary": (
            args.approval_boundary
            if args.approval_boundary is not None
            else predecessor.get("approval_boundary", "")
        ),
        "verification": "",
        "predecessor": predecessor_reference,
        "history": [],
    }
    append_history(state, f"resumed:{status}", resume_evidence, args.next_action)
    write_state_unlocked(args.new_state, state)
    return state


@serialized_state_paths("state")
def command_finish(args: argparse.Namespace) -> dict[str, Any]:
    state, raw_state = read_state_snapshot(args.state)
    expect_sha256 = hashlib.sha256(raw_state).hexdigest()
    require_running(state)
    if args.status == "complete" and not args.verification:
        raise StateError("complete requires --verification from a tool or artifact")
    if args.status in RESUMABLE_STATUSES:
        if args.next_action is None or not args.next_action.strip():
            raise StateError(f"{args.status} requires --next-action")
        next_action = args.next_action
    else:
        if args.next_action is not None:
            raise StateError(f"{args.status} does not accept --next-action")
        next_action = ""
    consume_budget(state, args.consume)
    state["progress_evidence"].extend(args.evidence)
    state["terminal_status"] = args.status
    state["next_action"] = next_action
    state["verification"] = args.verification or ""
    append_history(
        state, f"finished:{args.status}", args.evidence, state["next_action"]
    )
    write_state_unlocked(args.state, state, expect_sha256=expect_sha256)
    return state


@serialized_state_paths("state")
def command_annotate(args: argparse.Namespace) -> dict[str, Any]:
    state, raw_state = read_state_snapshot(args.state)
    actual_sha256 = hashlib.sha256(raw_state).hexdigest()
    if args.expect_sha256 != actual_sha256:
        raise StateError(
            "state fingerprint changed; refusing annotation "
            f"(expected {args.expect_sha256}, actual {actual_sha256})"
        )
    if (
        state["terminal_status"] in NON_RESUMABLE_STATUSES
        and args.next_action is not None
    ):
        raise StateError(f"{state['terminal_status']} does not accept --next-action")
    state["progress_evidence"].extend(args.evidence)
    if args.next_action is not None:
        if not args.next_action.strip():
            raise StateError("--next-action must be non-empty")
        state["next_action"] = args.next_action
    append_history(state, "annotated", args.evidence, state["next_action"])
    write_state_unlocked(args.state, state, expect_sha256=actual_sha256)
    return state


def command_fingerprint(args: argparse.Namespace) -> str:
    _, raw_state = read_state_snapshot(args.state)
    return hashlib.sha256(raw_state).hexdigest()


def index_line(state: dict[str, Any]) -> str:
    """One line: the index, not the log.

    SKILL.md asks the visible update to lead with state and the next action and
    to carry no recap prose, but the default output is the whole state document
    -- history included, so it grows every cycle. By cycle four a caller is
    piping each transition through its own extractor. This is that extractor,
    shipped.
    """
    budget = state["budget"]
    head = (
        f"{state['terminal_status']} "
        f"{budget['used']}/{budget['limit']} {budget['unit']}"
    )
    if state["terminal_status"] == "running":
        return f"{head} — next: {state['next_action']}"
    verification = state.get("verification") or ""
    return f"{head} — {verification}" if verification else head


def summary(state: dict[str, Any]) -> str:
    budget = state["budget"]
    return "\n".join(
        [
            f"goal: {state['goal']}",
            f"progress_evidence: {state['progress_evidence'][-1]}",
            f"budget: {budget['used']}/{budget['limit']} {budget['unit']}",
            f"next_action: {state['next_action']}",
            f"terminal_status: {state['terminal_status']}",
        ]
    )


def add_state_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--state", type=pathlib.Path, required=True)
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="emit one index line instead of the full state document",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    initialize = subparsers.add_parser("init", help="initialize a bounded run")
    add_state_argument(initialize)
    initialize.add_argument("--goal", required=True)
    initialize.add_argument("--evidence", action="append", required=True)
    initialize.add_argument("--budget-unit", required=True)
    initialize.add_argument("--budget-limit", type=int, required=True)
    initialize.add_argument("--next-action", required=True)
    initialize.add_argument("--allowed-effect", action="append", default=[])
    initialize.add_argument("--approval-boundary", default="")
    initialize.add_argument("--force", action="store_true")
    initialize.set_defaults(handler=command_init)

    advance = subparsers.add_parser(
        "advance",
        help="record a failed/nonterminal cycle and consume budget",
    )
    add_state_argument(advance)
    advance.add_argument("--evidence", action="append", required=True)
    advance.add_argument("--next-action", required=True)
    advance.add_argument("--consume", type=int, default=1)
    advance.set_defaults(handler=command_advance)

    resume = subparsers.add_parser(
        "resume",
        help="start a running successor from a resumable terminal state",
    )
    add_state_argument(resume)
    resume.add_argument("--new-state", type=pathlib.Path, required=True)
    resume.add_argument("--evidence", action="append", required=True)
    resume.add_argument("--extend-budget", type=int, default=0)
    resume.add_argument("--next-action", required=True)
    resume.add_argument("--allowed-effect", action="append", default=[])
    resume.add_argument("--approval-boundary")
    resume.set_defaults(handler=command_resume)

    finish = subparsers.add_parser("finish", help="record a terminal outcome")
    add_state_argument(finish)
    finish.add_argument("--status", choices=sorted(TERMINAL_STATUSES), required=True)
    finish.add_argument("--evidence", action="append", required=True)
    finish.add_argument("--verification")
    finish.add_argument("--next-action")
    finish.add_argument("--consume", type=int, default=0)
    finish.set_defaults(handler=command_finish)

    annotate = subparsers.add_parser(
        "annotate",
        help="append corrected evidence without changing status or budget",
    )
    add_state_argument(annotate)
    annotate.add_argument("--expect-sha256", required=True)
    annotate.add_argument("--evidence", action="append", required=True)
    annotate.add_argument("--next-action")
    annotate.set_defaults(handler=command_annotate)

    fingerprint = subparsers.add_parser(
        "fingerprint",
        help="print the SHA-256 of a validated state snapshot",
    )
    add_state_argument(fingerprint)
    fingerprint.set_defaults(handler=command_fingerprint)

    validate = subparsers.add_parser("validate", help="validate an existing state")
    add_state_argument(validate)
    validate.set_defaults(handler=lambda args: read_state(args.state))

    show = subparsers.add_parser("show", help="render the current contract")
    add_state_argument(show)
    show.add_argument("--json", action="store_true")
    show.set_defaults(handler=lambda args: read_state(args.state))
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "advance" and args.consume < 1:
        parser.error("--consume must be a positive integer")
    if args.command == "finish" and args.consume < 0:
        parser.error("--consume must be zero or a positive integer")
    if args.command == "resume" and args.extend_budget < 0:
        parser.error("--extend-budget must be zero or a positive integer")
    try:
        state = args.handler(args)
    except StateError as exc:
        print(f"loop-state: {exc}", file=sys.stderr)
        return 3
    if args.command == "fingerprint":
        print(state)
    elif getattr(args, "quiet", False):
        print(index_line(state))
    elif args.command == "show" and not args.json:
        print(summary(state))
    else:
        print(json.dumps(state, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
