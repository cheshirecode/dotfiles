#!/usr/bin/env python3
"""Self-diagnosis for the pr-cost skill, one lane per harness.

The thing this replaces was a handover note: prose telling a human to run
four commands and eyeball the output. Prose cannot tell you that a lane
broke. It also froze one machine's absolute paths, one interpreter, and one
PR number into the only copy of the procedure.

A lane is one harness plus the reader that turns its transcript into a cost.
Every lane is classified, and the classification is the whole point:

  ok           reader ran and satisfied the shared contract
  broken       reader ran and violated it, or crashed        -> exit 1
  no-signal    reader returned a cost of zero from real input -> exit 1
  unavailable  lane exists, no transcript on this machine
  adapter-only a hook adapter exists, no usage reader
  unsupported  the skill claims no lane for this harness

Only `broken` and `no-signal` fail. `unavailable` must never read as `ok`:
a machine without Codex installed is not a Codex lane that works, and the
difference between those two is the entire value of running this.

`--self-check` is the portable mode. It runs every lane against a synthetic
transcript this file generates, so the contract is provable on a machine
that has none of these harnesses installed, and in CI. `--live` adds the
lanes that need a real transcript. Default runs both, and skips live lanes
that have nothing to read.

USD is reported per lane, because the lanes do not price alike. The claude
and codex readers fall back to fixed default rates for unknown models:
`default-rates`. A model name matching the reader's rate table prices the
session at that model's public list prices: `model-rates`. The codex reader
prices its cached input at the cache-read rate; the claude reader prices the
cache read/write split directly. The opencode reader passes through the
provider's own billed cost: `provider-reported`. None of the three is
`measured` — nothing here checks any figure against an invoice — and a single
basis asserted for all three would misdescribe whichever lane it did not
match.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any

SCRIPTS = pathlib.Path(__file__).resolve().parent
SKILL = SCRIPTS.parent

# What a consumer may rely on from any lane, whatever the harness. Keys
# outside this set are a lane's own business: claude reports a cache split,
# codex reports cwd, and no caller may assume either.
SHARED_KEYS = (
    "session_id",
    "model",
    "tokens_in",
    "tokens_out",
    "window_start",
    "window_end",
    "path",
    "usd_estimated",
)

# A synthetic transcript per lane, with distinct non-round token counts so a
# wrong field pairing cannot coincidentally balance.
# One fixture per reader lane: how to build it, and what to call it.
# Values are distinct and non-round so a wrong field pairing cannot
# coincidentally reproduce the right total.
_JSONL_EVENTS = {
    "claude": [
        {
            "type": "user",
            "sessionId": "doctor-claude",
            "timestamp": "2026-01-01T00:00:00Z",
            "message": {"role": "user", "content": "x"},
        },
        {
            "type": "assistant",
            "sessionId": "doctor-claude",
            "timestamp": "2026-01-01T00:01:00Z",
            "message": {
                "role": "assistant",
                "id": "msg_1",
                "model": "doctor-model",
                "usage": {
                    "input_tokens": 13,
                    "output_tokens": 27,
                    "cache_read_input_tokens": 101,
                    "cache_creation_input_tokens": 59,
                },
            },
        },
    ],
    "codex": [
        {
            "type": "session_meta",
            "timestamp": "2026-01-01T00:00:00Z",
            "payload": {
                "session_id": "doctor-codex",
                "cwd": "/doctor",
                "model": "doctor-model",
                "timestamp": "2026-01-01T00:00:00Z",
            },
        },
        {
            "type": "event_msg",
            "timestamp": "2026-01-01T00:01:00Z",
            "payload": {
                "type": "token_count",
                "info": {"total_token_usage": {
                    "input_tokens": 173,
                    "output_tokens": 31,
                    "cached_input_tokens": 101,
                }},
            },
        },
    ],
}

def display_path(path: pathlib.Path) -> str:
    """Path relative to the skill when it lives there, absolute otherwise.

    `relative_to` raises on any path outside the skill, which a test lane
    always is. Reporting must never be the thing that crashes the report.
    """
    try:
        return str(path.relative_to(SKILL))
    except ValueError:
        return str(path)


def write_jsonl(events: list[dict], target: pathlib.Path) -> None:
    target.write_text(
        "".join(json.dumps(e) + "\n" for e in events), encoding="utf-8"
    )


def write_opencode_db(target: pathlib.Path) -> None:
    """Build a minimal opencode database with one billed assistant message.

    opencode stores sessions in SQLite, not JSONL, so its synthetic fixture
    has to be a real database. Distinct non-round counts, same as the other
    lanes, so no wrong field pairing reproduces the right total.
    """
    import sqlite3

    conn = sqlite3.connect(target)
    try:
        conn.execute(
            "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT)"
        )
        conn.execute(
            "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, "
            "time_created INTEGER, data TEXT)"
        )
        conn.execute(
            "INSERT INTO session VALUES ('doctor-opencode', '/doctor')"
        )
        conn.execute(
            "INSERT INTO message VALUES ('m1', 'doctor-opencode', ?, ?)",
            (
                1767225600000,
                json.dumps(
                    {
                        "role": "assistant",
                        "modelID": "doctor-model",
                        "providerID": "doctor-provider",
                        "cost": 0.0123,
                        "tokens": {
                            "input": 13,
                            "output": 27,
                            "reasoning": 7,
                            "cache": {"read": 101, "write": 59},
                        },
                    }
                ),
            ),
        )
        conn.commit()
    finally:
        conn.close()


SYNTHETIC = {
    "claude": {
        "suffix": ".jsonl",
        "build": lambda p: write_jsonl(_JSONL_EVENTS["claude"], p),
    },
    "codex": {
        "suffix": ".jsonl",
        "build": lambda p: write_jsonl(_JSONL_EVENTS["codex"], p),
    },
    "opencode": {"suffix": ".db", "build": write_opencode_db},
}


def lanes() -> list[dict[str, Any]]:
    """Declare every lane the skill claims, with how to reach it."""
    return [
        {
            "harness": "claude",
            "reader": SCRIPTS / "claude_session_usage.py",
            "flag": "--jsonl",
            "live_root": pathlib.Path.home() / ".claude" / "projects",
            "live_glob": "*/*.jsonl",
        },
        {
            "harness": "codex",
            "reader": SCRIPTS / "codex_session_usage.py",
            "flag": "--path",
            "live_root": pathlib.Path.home() / ".codex" / "sessions",
            "live_glob": "**/rollout-*.jsonl",
        },
        {
            "harness": "cursor",
            "reader": None,
            "adapter": SKILL / "adapters" / "cursor" / "hooks.json",
        },
        {
            "harness": "opencode",
            "reader": SCRIPTS / "opencode_session_usage.py",
            "flag": "--db",
            "live_root": pathlib.Path.home() / ".local" / "share" / "opencode",
            "live_glob": "opencode.db",
        },
    ]


def run_reader(reader: pathlib.Path, flag: str, target: pathlib.Path) -> dict[str, Any]:
    """Run one reader and return its verdict, never raising on its failure."""
    proc = subprocess.run(
        [sys.executable, str(reader), flag, str(target)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return {
            "status": "broken",
            "detail": f"reader exited {proc.returncode}: "
            f"{(proc.stderr or proc.stdout).strip()[:200]}",
        }
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return {"status": "broken", "detail": f"reader stdout is not JSON: {exc}"}
    if not isinstance(payload, dict):
        return {"status": "broken", "detail": "reader stdout is not a JSON object"}

    missing = [k for k in SHARED_KEYS if k not in payload]
    if missing:
        return {
            "status": "broken",
            "detail": f"missing shared keys: {', '.join(missing)}",
            "payload": payload,
        }
    for key in ("tokens_in", "tokens_out"):
        value = payload[key]
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            return {
                "status": "broken",
                "detail": f"{key} is {value!r}, want a non-negative integer",
                "payload": payload,
            }
    start, end = payload["window_start"], payload["window_end"]
    if isinstance(start, str) and isinstance(end, str) and end < start:
        return {
            "status": "broken",
            "detail": f"window_end {end} precedes window_start {start}",
            "payload": payload,
        }
    if payload["tokens_in"] == 0 and payload["tokens_out"] == 0:
        # A reader that answers "this session cost $0.0000" instead of
        # failing hands a confident wrong number to a PR comment. Zero is
        # not an estimate; it is the absence of one.
        return {
            "status": "no-signal",
            "detail": "reader reported zero tokens both ways; "
            "a zero-cost estimate is not an estimate",
            "payload": payload,
        }
    # The same reasoning, applied to the number this skill exists to produce.
    # Counting tokens correctly while pricing them at zero is a lost rate
    # table, and the token guard above cannot see it: it matches tokens,
    # which is adjacent to what was meant. Per lane, because the bases differ
    # — a fixed rate table cannot reach zero on a non-empty transcript, but a
    # provider-reported cost legitimately can for a free request.
    basis = payload.get("usd_basis", "default-rates")
    usd = payload["usd_estimated"]
    if basis != "provider-reported" and isinstance(usd, (int, float)) and usd == 0:
        return {
            "status": "no-signal",
            "detail": f"reader counted {payload['tokens_in']} input tokens but "
            f"priced them at $0 on a {basis} lane; the rate table is missing",
            "payload": payload,
        }
    return {"status": "ok", "payload": payload}


def synthetic_lane(lane: dict[str, Any], tmp: pathlib.Path) -> dict[str, Any]:
    spec = SYNTHETIC[lane["harness"]]
    target = tmp / f"{lane['harness']}{spec['suffix']}"
    spec["build"](target)
    return run_reader(lane["reader"], lane["flag"], target)


def live_lane(lane: dict[str, Any]) -> dict[str, Any]:
    root = lane["live_root"]
    if not root.is_dir():
        return {"status": "unavailable", "detail": f"{root} does not exist"}
    newest = None
    for candidate in root.glob(lane["live_glob"]):
        if candidate.is_file() and candidate.stat().st_size > 0:
            if newest is None or candidate.stat().st_mtime > newest.stat().st_mtime:
                newest = candidate
    if newest is None:
        return {"status": "unavailable", "detail": f"no transcript under {root}"}
    result = run_reader(lane["reader"], lane["flag"], newest)
    result["transcript"] = str(newest)
    return result


def diagnose(*, self_check: bool, live: bool) -> dict[str, Any]:
    report: dict[str, Any] = {
        "schema_version": "pr-cost-doctor/v1",
        "usd_basis": {},
        "usd_basis_note": (
            "The claude and codex readers price every session at fixed default "
            "rates and never use the model name they report, so their USD is "
            "estimated, not measured, whatever model ran. The opencode reader "
            "reports the provider's own billed cost. Never assume every lane's "
            "figure is the same kind of number."
        ),
        "shared_keys": list(SHARED_KEYS),
        "lanes": [],
    }
    with tempfile.TemporaryDirectory() as raw:
        tmp = pathlib.Path(raw)
        for lane in lanes():
            entry: dict[str, Any] = {"harness": lane["harness"]}
            if lane["reader"] is None:
                adapter = lane.get("adapter")
                if adapter is not None and adapter.exists():
                    entry["status"] = "adapter-only"
                    entry["detail"] = (
                        f"hook adapter at {display_path(adapter)}, "
                        "no usage reader"
                    )
                else:
                    entry["status"] = "unsupported"
                    entry["detail"] = "no adapter and no usage reader"
                report["lanes"].append(entry)
                continue
            if not lane["reader"].exists():
                entry["status"] = "broken"
                entry["detail"] = f"declared reader {lane['reader']} is missing"
                report["lanes"].append(entry)
                continue
            if self_check:
                entry["self_check"] = synthetic_lane(lane, tmp)
            if live:
                entry["live"] = live_lane(lane)
            # Read the basis from the lane itself rather than assuming one.
            # opencode reports the provider's billed cost; the other two
            # price from a fixed rate table. Claiming a single basis for all
            # of them would misdescribe whichever lane it did not match.
            for key in ("self_check", "live"):
                payload = entry.get(key, {}).get("payload")
                if isinstance(payload, dict):
                    report["usd_basis"][lane["harness"]] = payload.get(
                        "usd_basis", "default-rates"
                    )
                    break
            statuses = [
                entry[k]["status"] for k in ("self_check", "live") if k in entry
            ]
            # A lane is only as good as its worst run, but an absent live
            # transcript never demotes a self-check that passed.
            if "broken" in statuses:
                entry["status"] = "broken"
            elif "no-signal" in statuses:
                entry["status"] = "no-signal"
            elif "ok" in statuses:
                entry["status"] = "ok"
            else:
                entry["status"] = "unavailable"
            report["lanes"].append(entry)
    report["failed"] = sorted(
        lane["harness"]
        for lane in report["lanes"]
        if lane["status"] in ("broken", "no-signal")
    )
    return report


def render(report: dict[str, Any]) -> str:
    width = max(len(lane["harness"]) for lane in report["lanes"])
    rows = []
    for lane in report["lanes"]:
        # Always show the sub-run statuses. Without them a lane whose live
        # transcript is missing reads as a flat `ok`, which is the one
        # confusion this tool exists to prevent.
        runs = " ".join(
            f"{key.replace('_', '-')}={lane[key]['status']}"
            for key in ("self_check", "live")
            if key in lane
        )
        detail = lane.get("detail")
        if detail is None:
            for key in ("live", "self_check"):
                if key in lane and lane[key].get("detail"):
                    detail = lane[key]["detail"]
                    break
        rows.append(
            f"  {lane['harness']:<{width}}  {lane['status']:<12}  "
            f"{runs:<28}  {detail or ''}".rstrip()
        )
    verdict = (
        "FAIL: " + ", ".join(report["failed"])
        if report["failed"]
        else "OK: no lane is broken"
    )
    basis = ", ".join(
        f"{harness}={value}" for harness, value in sorted(report["usd_basis"].items())
    )
    return "\n".join(
        ["pr-cost doctor", *rows, "", f"usd_basis: {basis or 'none measured'}", verdict]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--self-check",
        action="store_true",
        help="run lanes against synthetic transcripts only (portable, no harness needed)",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="run lanes against this machine's newest real transcript",
    )
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    args = parser.parse_args()
    # Neither flag means both: the useful default is the full picture.
    self_check = args.self_check or not args.live
    live = args.live or not args.self_check
    report = diagnose(self_check=self_check, live=live)
    if args.json:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print(render(report))
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
