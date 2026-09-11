#!/usr/bin/env python3
"""Collect and annotate per-PR AI cost payloads."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any


SCHEMA_VERSION = "pr-cost/v1"
HARNESSES = {"claude", "cursor", "codex", "opencode"}
CONFIDENCE_LEVELS = {"metered", "estimated", "unavailable"}
USD_BASES = {"model-rates", "default-rates", "provider-reported"}
SCOPES = {"session-total", "this-pr"}

# tokens_in is the sum of three token classes that cost three different
# amounts. A reader who sees only the total reads it as uncached input and
# multiplies by the input rate. On one real posted comment that produced a
# large over-reading: tokens_in 721,979,117 next to usd ~510, where 96.8% of
# the total was cache reads billed at a tenth of the input rate.
#
# These keys carry the parts, the basis, and what the window covers, so the
# total can be read. They are additive and nullable, so a pr-cost/v1 payload
# written before they existed still validates -- the version does not move.
OPTIONAL_FIELDS = (
    "tokens_in_uncached",
    "tokens_in_cache_read",
    "tokens_in_cache_write",
    "usd_basis",
    "scope",
)
DEFAULT_LEDGER = "~/.local/share/pr-cost/ledger.jsonl"
PR_URL_PATTERN = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/\d+")


class PrCostError(ValueError):
    """Raised when the collector receives invalid input."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def is_iso_timestamp(value: str) -> bool:
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def validate_nullable_string(payload: dict[str, Any], field: str) -> None:
    value = payload.get(field)
    if value is None:
        return
    if not isinstance(value, str) or not value.strip():
        raise PrCostError(f"{field} must be a non-empty string or null")


def validate_nullable_integer(payload: dict[str, Any], field: str) -> None:
    value = payload.get(field)
    if value is None:
        return
    if not isinstance(value, int) or isinstance(value, bool):
        raise PrCostError(f"{field} must be an integer or null")


def validate_payload(payload: dict[str, Any]) -> dict[str, Any]:
    required_fields = (
        "schema_version",
        "harness",
        "confidence",
        "usd",
        "tokens_in",
        "tokens_out",
        "model",
        "session_id",
        "window_start",
        "window_end",
        "pr_url",
        "generated_at",
    )
    for field in required_fields:
        if field not in payload:
            raise PrCostError(f"missing required field: {field}")

    if payload["schema_version"] != SCHEMA_VERSION:
        raise PrCostError(f"schema_version must be {SCHEMA_VERSION}")
    if payload["harness"] not in HARNESSES:
        raise PrCostError("harness must be one of claude, cursor, codex")
    if payload["confidence"] not in CONFIDENCE_LEVELS:
        raise PrCostError("confidence must be metered, estimated, or unavailable")

    usd = payload["usd"]
    if usd is not None and not is_number(usd):
        raise PrCostError("usd must be a number or null")
    validate_nullable_integer(payload, "tokens_in")
    validate_nullable_integer(payload, "tokens_out")
    validate_nullable_string(payload, "model")
    validate_nullable_string(payload, "session_id")
    validate_nullable_string(payload, "pr_url")
    notes = payload.get("notes")
    if notes is not None and (not isinstance(notes, str) or not notes.strip()):
        raise PrCostError("notes must be a non-empty string or null")

    for field in ("tokens_in_uncached", "tokens_in_cache_read", "tokens_in_cache_write"):
        if field in payload:
            validate_nullable_integer(payload, field)
    usd_basis = payload.get("usd_basis")
    if usd_basis is not None and usd_basis not in USD_BASES:
        raise PrCostError("usd_basis must be one of " + ", ".join(sorted(USD_BASES)) + ", or null")
    scope = payload.get("scope")
    if scope is not None and scope not in SCOPES:
        raise PrCostError("scope must be one of " + ", ".join(sorted(SCOPES)) + ", or null")

    # A split that does not add up to the total is worse than no split: both
    # numbers are then in the comment, and a reader has no way to tell which
    # one to believe.
    parts = [
        payload.get(field)
        for field in ("tokens_in_uncached", "tokens_in_cache_read", "tokens_in_cache_write")
    ]
    if payload.get("tokens_in") is not None and all(part is not None for part in parts):
        if sum(parts) != payload["tokens_in"]:
            raise PrCostError(
                f"tokens_in ({payload['tokens_in']}) must equal uncached + cache read + "
                f"cache write ({sum(parts)})"
            )

    for field in ("window_start", "window_end", "generated_at"):
        value = payload.get(field)
        if not isinstance(value, str) or not value.strip() or not is_iso_timestamp(value):
            raise PrCostError(f"{field} must be a valid ISO 8601 timestamp")

    pr_url = payload["pr_url"]
    if pr_url is not None and not PR_URL_PATTERN.fullmatch(pr_url):
        raise PrCostError("pr_url must be a GitHub pull request URL or null")
    return payload


def read_json_file(path: pathlib.Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise PrCostError(f"fixture does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise PrCostError(f"fixture is not valid JSON: {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise PrCostError(f"fixture must contain a JSON object: {path}")
    return raw


def read_json_stdin() -> dict[str, Any]:
    raw_stdin = sys.stdin.read().strip()
    if not raw_stdin:
        raise PrCostError("stdin JSON is required")
    try:
        value = json.loads(raw_stdin)
    except json.JSONDecodeError as exc:
        raise PrCostError(f"stdin is not valid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise PrCostError("stdin JSON must be an object")
    return value


def default_confidence(harness: str, usd: float | int | None, tokens_known: bool) -> str:
    if usd is not None:
        return "estimated"
    if harness == "claude" and tokens_known:
        return "estimated"
    return "unavailable"


def default_notes(harness: str, confidence: str) -> str | None:
    if confidence != "unavailable":
        return None
    if harness == "cursor":
        return "Cursor hook payloads do not expose cost or token usage."
    if harness == "codex":
        return "Codex has no native PR creation hook or local cost payload."
    if harness == "opencode":
        # The only lane that does not need this branch to apologise for a
        # missing number: opencode records the provider's billed cost, so
        # `unavailable` here means the payload never reached the collector,
        # not that the harness cannot produce one.
        return "opencode records provider-billed cost; none reached this payload."
    return "Hook payload did not include enough data to estimate session cost."


def payload_from_args(
    args: argparse.Namespace,
    *,
    default_pr_url: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if getattr(args, "fixture", None):
        payload.update(read_json_file(args.fixture))

    generated_at = args.generated_at or payload.get("generated_at") or utc_now()
    tokens_known = args.tokens_in is not None or args.tokens_out is not None
    harness = args.harness or payload.get("harness")
    if harness not in HARNESSES:
        raise PrCostError("harness is required and must be one of claude, cursor, codex")
    confidence = (
        args.confidence
        or payload.get("confidence")
        or default_confidence(harness, args.usd if args.usd is not None else payload.get("usd"), tokens_known)
    )

    payload.update(
        {
            "schema_version": SCHEMA_VERSION,
            "harness": harness,
            "confidence": confidence,
            "usd": args.usd if args.usd is not None else payload.get("usd"),
            "tokens_in": args.tokens_in if args.tokens_in is not None else payload.get("tokens_in"),
            "tokens_out": args.tokens_out if args.tokens_out is not None else payload.get("tokens_out"),
            "model": args.model if args.model is not None else payload.get("model"),
            "session_id": args.session_id if args.session_id is not None else payload.get("session_id"),
            "window_start": args.window_start or payload.get("window_start") or generated_at,
            "window_end": args.window_end or payload.get("window_end") or generated_at,
            "pr_url": args.pr_url if args.pr_url is not None else payload.get("pr_url", default_pr_url),
            "generated_at": generated_at,
        }
    )

    for field in OPTIONAL_FIELDS:
        supplied = getattr(args, field, None)
        payload[field] = supplied if supplied is not None else payload.get(field)

    # A session reader sums a whole session: several PRs plus unrelated work,
    # if that is what the window held. Saying so by default is the honest
    # label; a caller who really did scope the numbers to one PR passes
    # --scope this-pr.
    if payload.get("scope") is None and payload.get("tokens_in") is not None:
        payload["scope"] = "session-total"

    if args.notes is not None:
        payload["notes"] = args.notes
    elif "notes" not in payload:
        payload["notes"] = default_notes(harness, confidence)

    return validate_payload(payload)


def ledger_path(argument: pathlib.Path | None) -> pathlib.Path:
    configured = argument or pathlib.Path(os.environ.get("PR_COST_LEDGER", DEFAULT_LEDGER)).expanduser()
    return configured.expanduser()


def load_ledger(path: pathlib.Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), start=1):
        if not raw_line.strip():
            continue
        try:
            parsed = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            raise PrCostError(f"ledger line {line_number} is not valid JSON: {path}") from exc
        if not isinstance(parsed, dict):
            raise PrCostError(f"ledger line {line_number} must be a JSON object: {path}")
        rows.append(parsed)
    return rows


def same_annotation(existing: dict[str, Any], payload: dict[str, Any]) -> bool:
    return (
        existing.get("pr_url") == payload.get("pr_url")
        and existing.get("session_id") == payload.get("session_id")
    )


def append_ledger(
    path: pathlib.Path, payload: dict[str, Any], *, allow_duplicate: bool = False
) -> str:
    """Append one row. Returns "annotated", "corrected", or "duplicate".

    The guard keys on pr_url + session_id, so a re-run carrying a corrected
    figure for the same session looks identical to an accidental replay. With
    `allow_duplicate` the corrected row is appended rather than replacing the
    first, so the ledger keeps both what was published and what replaced it.
    """
    rows = load_ledger(path)
    duplicate = any(same_annotation(row, payload) for row in rows)
    if duplicate and not allow_duplicate:
        return "duplicate"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True))
        handle.write("\n")
    return "corrected" if duplicate else "annotated"


USD_BASIS_TEXT = {
    "model-rates": "the published rates of the model named above",
    "default-rates": "fixed lane rates, NOT the rates of the model named above",
    "provider-reported": "the cost the provider recorded, copied not recomputed",
}

SCOPE_TEXT = {
    "session-total": "whole session, which may cover other PRs and unrelated work",
    "this-pr": "scoped to this PR",
}


def human_summary(payload: dict[str, Any]) -> list[str]:
    """The lines a reader sees before the JSON block.

    The JSON alone put `tokens_in` next to `usd` with nothing between them,
    and a reader who knows the input rate multiplies one by the other. These
    lines say which parts of tokens_in cost what, on what basis the USD was
    priced, and what work the window covers.
    """
    lines: list[str] = []

    usd = payload.get("usd")
    headline = f"~${usd:,.2f}" if isinstance(usd, (int, float)) else "cost unavailable"
    model = payload.get("model") or "model unknown"
    confidence = payload.get("confidence") or "unknown"
    lines.append(f"**{headline}** — {model} — confidence: {confidence}")

    basis = payload.get("usd_basis")
    if basis:
        lines.append(f"- Priced from: {basis} ({USD_BASIS_TEXT.get(basis, 'see the skill docs')})")

    tokens_in = payload.get("tokens_in")
    uncached = payload.get("tokens_in_uncached")
    cache_read = payload.get("tokens_in_cache_read")
    cache_write = payload.get("tokens_in_cache_write")
    if tokens_in is not None and None not in (uncached, cache_read, cache_write):
        share = f" ({cache_read / tokens_in:.1%} of input)" if tokens_in else ""
        lines.append(
            f"- Input {tokens_in:,} = {uncached:,} uncached + {cache_read:,} cache read"
            f"{share} + {cache_write:,} cache write. Cache reads bill at a fraction "
            "of the input rate, so this total is not input-priced."
        )
    elif tokens_in is not None:
        lines.append(
            f"- Input {tokens_in:,} tokens, cached and uncached combined; "
            "this lane did not report the split."
        )

    tokens_out = payload.get("tokens_out")
    if tokens_out is not None:
        lines.append(f"- Output {tokens_out:,} tokens")

    scope = payload.get("scope")
    if scope:
        lines.append(f"- Covers: {SCOPE_TEXT.get(scope, scope)}")

    return lines


def comment_body(payload: dict[str, Any]) -> str:
    session_marker = payload.get("session_id") or "unknown"
    summary = "\n".join(human_summary(payload))
    return (
        f"<!-- pr-cost:{session_marker} -->\n"
        "AI cost payload for the session that created this PR:\n\n"
        f"{summary}\n\n"
        "```json\n"
        f"{json.dumps(payload, indent=2, sort_keys=True)}\n"
        "```"
    )


def maybe_comment_pr(payload: dict[str, Any], live: bool) -> bool:
    if not live or not payload.get("pr_url"):
        return False
    subprocess.run(
        [
            "gh",
            "pr",
            "comment",
            payload["pr_url"],
            "--body",
            comment_body(payload),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return True


def command_emit(args: argparse.Namespace) -> dict[str, Any]:
    return payload_from_args(args)


def command_annotate(args: argparse.Namespace) -> dict[str, Any]:
    payload = payload_from_args(args)
    target_ledger = ledger_path(args.ledger)
    status = append_ledger(target_ledger, payload, allow_duplicate=args.allow_duplicate)
    commented = False
    if status != "duplicate":
        commented = maybe_comment_pr(payload, live=os.environ.get("PR_COST_HOOK_LIVE") == "1")
    return {
        "status": status,
        "ledger": str(target_ledger),
        "commented": commented,
        "payload": payload,
    }


def extract_command(payload: dict[str, Any]) -> tuple[str | None, str | None, int | None]:
    if isinstance(payload.get("command"), str):
        return payload["command"], payload.get("stdout"), payload.get("exit_code")
    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input")
    tool_response = payload.get("tool_response")
    if tool_name == "Shell" and isinstance(tool_input, dict) and isinstance(tool_response, dict):
        return (
            tool_input.get("command"),
            tool_response.get("stdout"),
            tool_response.get("exit_code"),
        )
    return None, None, None


def detect_harness(args: argparse.Namespace, hook_payload: dict[str, Any]) -> str:
    if args.harness:
        return args.harness
    if "tool_name" in hook_payload:
        return "claude"
    if "command" in hook_payload:
        return "cursor"
    return "codex"


def is_pr_create_command(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if "gh" not in tokens or "pr" not in tokens:
        return False
    for index, token in enumerate(tokens):
        if token != "gh":
            continue
        remainder = tokens[index + 1 :]
        if "pr" not in remainder:
            continue
        pr_index = remainder.index("pr")
        if pr_index + 1 >= len(remainder):
            continue
        return remainder[pr_index + 1] == "create"
    return False


def extract_pr_url(stdout: str | None) -> str | None:
    if not stdout:
        return None
    match = PR_URL_PATTERN.search(stdout)
    return match.group(0) if match else None


def fail_open(message: str, *, extra: dict[str, Any] | None = None) -> int:
    response = {"status": "ignored", "reason": message}
    if extra:
        response.update(extra)
    print(json.dumps(response, sort_keys=True))
    return 0


def command_from_hook(args: argparse.Namespace) -> int:
    try:
        hook_payload = read_json_stdin()
        command, stdout, exit_code = extract_command(hook_payload)
        if not command or not is_pr_create_command(command):
            return fail_open("not-pr-create")
        if exit_code not in (0, None):
            return fail_open("command-failed")
        pr_url = extract_pr_url(stdout)
        if pr_url is None:
            return fail_open("missing-pr-url")

        args.harness = detect_harness(args, hook_payload)
        args.pr_url = pr_url
        payload = payload_from_args(args, default_pr_url=pr_url)
        target_ledger = ledger_path(args.ledger)
        # No --allow-duplicate here on purpose: a hook that re-fires must stay
        # idempotent, or one retried PR create posts the cost twice.
        status = append_ledger(target_ledger, payload)
        commented = False
        if status != "duplicate":
            commented = maybe_comment_pr(payload, live=os.environ.get("PR_COST_HOOK_LIVE") == "1")
        print(
            json.dumps(
                {
                    "status": status,
                    "ledger": str(target_ledger),
                    "commented": commented,
                    "payload": payload,
                },
                sort_keys=True,
            )
        )
        return 0
    except Exception as exc:  # pragma: no cover - fail-open path is behaviorally required
        return fail_open("error", extra={"detail": str(exc)})


def add_payload_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--fixture", type=pathlib.Path, help="read a payload fixture JSON object")
    parser.add_argument("--harness", choices=sorted(HARNESSES))
    parser.add_argument("--confidence", choices=sorted(CONFIDENCE_LEVELS))
    parser.add_argument("--usd", type=float)
    parser.add_argument("--tokens-in", type=int, dest="tokens_in")
    parser.add_argument("--tokens-out", type=int, dest="tokens_out")
    parser.add_argument("--model")
    parser.add_argument("--session-id", dest="session_id")
    parser.add_argument("--window-start")
    parser.add_argument("--window-end")
    parser.add_argument("--pr-url")
    parser.add_argument("--generated-at")
    parser.add_argument("--notes")
    parser.add_argument("--tokens-in-uncached", type=int, dest="tokens_in_uncached")
    parser.add_argument("--tokens-in-cache-read", type=int, dest="tokens_in_cache_read")
    parser.add_argument("--tokens-in-cache-write", type=int, dest="tokens_in_cache_write")
    parser.add_argument("--usd-basis", dest="usd_basis", choices=sorted(USD_BASES))
    parser.add_argument("--scope", dest="scope", choices=sorted(SCOPES))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    emit = subparsers.add_parser("emit", help="print a validated payload")
    add_payload_arguments(emit)
    emit.set_defaults(handler=command_emit)

    annotate = subparsers.add_parser("annotate", help="append payload to local ledger and optionally comment")
    add_payload_arguments(annotate)
    annotate.add_argument("--ledger", type=pathlib.Path)
    annotate.add_argument(
        "--allow-duplicate",
        dest="allow_duplicate",
        action="store_true",
        help="publish a corrected figure for a session already in the ledger",
    )
    annotate.set_defaults(handler=command_annotate)

    from_hook = subparsers.add_parser("from-hook", help="parse hook stdin and annotate matching PR creates")
    add_payload_arguments(from_hook)
    from_hook.add_argument("--ledger", type=pathlib.Path)
    from_hook.set_defaults(handler=command_from_hook)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        result = args.handler(args)
        if args.command == "from-hook":
            return result
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except PrCostError as exc:
        print(f"pr-cost: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
