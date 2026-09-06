#!/usr/bin/env python3
"""Sum assistant token usage for one opencode session.

opencode keeps sessions in a SQLite database rather than a JSONL file, so
this reader takes `--db` where the others take a transcript path. It also
records something the other two harnesses do not: the provider's own `cost`
per message. That number is billed, not inferred, so this lane reports
usd_basis `provider-reported` while the claude and codex lanes report
`default-rates`. A consumer must not assume every lane's USD is a guess.

Token shape, verified against real rows: `input` excludes cache, and
`total` == input + output + reasoning + cache.read + cache.write. Reasoning
tokens are generated and billed as output, so they are counted in
tokens_out; the split is also reported separately.

Sessions carry the `directory` they ran in, so --cwd narrows to the repo you
care about instead of whatever ran most recently on this machine.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sqlite3
import sys
from typing import Any

DEFAULT_DB = pathlib.Path.home() / ".local" / "share" / "opencode" / "opencode.db"

# Assistant rows only. A row with no token object is a message the model
# never billed for (an aborted turn, a tool relay); it still proves the
# format is understood, so it is counted as seen but contributes nothing.
ROWS = """
SELECT m.session_id,
       m.time_created,
       json_extract(m.data, '$.tokens.input')        AS input,
       json_extract(m.data, '$.tokens.output')       AS output,
       json_extract(m.data, '$.tokens.reasoning')    AS reasoning,
       json_extract(m.data, '$.tokens.cache.read')   AS cache_read,
       json_extract(m.data, '$.tokens.cache.write')  AS cache_write,
       json_extract(m.data, '$.cost')                AS cost,
       json_extract(m.data, '$.modelID')             AS model,
       json_extract(m.data, '$.providerID')          AS provider
FROM message m
WHERE json_extract(m.data, '$.role') = 'assistant'
"""


def pick_session(
    conn: sqlite3.Connection, cwd: str | None
) -> str | None:
    """Newest session with assistant turns, optionally by directory.

    Deliberately does NOT require a readable token object. Requiring one
    made a schema change across every session report "no session with
    usage" — which reads as "you have never used opencode" rather than
    "this reader no longer understands the rows it is reading". Selecting
    on assistant turns alone lets the guard below tell those apart.
    """
    sql = (
        "SELECT m.session_id FROM message m "
        "JOIN session s ON s.id = m.session_id "
        "WHERE json_extract(m.data, '$.role') = 'assistant' "
    )
    params: list[Any] = []
    if cwd is not None:
        sql += "  AND s.directory = ? "
        params.append(cwd)
    sql += "GROUP BY m.session_id ORDER BY MAX(m.time_created) DESC LIMIT 1"
    row = conn.execute(sql, params).fetchone()
    return row[0] if row else None


def session_usage(
    db: pathlib.Path, session_id: str | None, cwd: str | None
) -> dict[str, Any]:
    if not db.exists():
        raise SystemExit(f"no opencode database at {db}")
    # Read-only: this database belongs to a running application.
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        if session_id is None:
            session_id = pick_session(conn, cwd)
            if session_id is None:
                where = f" for cwd {cwd}" if cwd else ""
                raise SystemExit(f"no opencode session with usage{where} in {db}")
        rows = conn.execute(
            ROWS + " AND m.session_id = ? ORDER BY m.time_created", (session_id,)
        ).fetchall()
        directory = conn.execute(
            "SELECT directory FROM session WHERE id = ?", (session_id,)
        ).fetchone()
    finally:
        conn.close()

    seen = len(rows)
    priced = [r for r in rows if r[2] is not None]

    # Same guard as the claude reader: assistant turns with no readable token
    # object anywhere is a schema change, not a free session. Reporting $0
    # for it would be a confident wrong number.
    if seen and not priced:
        raise SystemExit(
            f"{db}: session {session_id} has {seen} assistant message(s), none "
            "carrying a readable token object. The opencode schema changed or "
            "this reader is out of date; a zero-cost estimate would be wrong "
            "rather than cheap."
        )

    def total(index: int) -> int:
        return sum(int(r[index] or 0) for r in priced)

    uncached, output = total(2), total(3)
    reasoning, cache_read, cache_write = total(4), total(5), total(6)
    cost = round(sum(float(r[7] or 0.0) for r in priced), 6)
    model = next((r[8] for r in reversed(priced) if r[8]), None)
    provider = next((r[9] for r in reversed(priced) if r[9]), None)

    def stamp(index: int) -> str | None:
        if not rows:
            return None
        import datetime

        ms = rows[index][1]
        return (
            datetime.datetime.fromtimestamp(
                ms / 1000, datetime.timezone.utc
            ).isoformat().replace("+00:00", "Z")
        )

    return {
        "session_id": session_id,
        "model": model,
        "provider": provider,
        "tokens_in": uncached + cache_read + cache_write,
        "tokens_out": output + reasoning,
        "uncached_input_tokens": uncached,
        "reasoning_tokens": reasoning,
        "cache_read_input_tokens": cache_read,
        "cache_creation_input_tokens": cache_write,
        "assistant_messages_seen": seen,
        "unique_assistant_messages": len(priced),
        "window_start": stamp(0),
        "window_end": stamp(-1),
        "cwd": directory[0] if directory else None,
        "path": str(db),
        # Billed by the provider, not inferred from a rate table.
        "usd_estimated": cost,
        "usd_basis": "provider-reported",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--db", type=pathlib.Path, default=DEFAULT_DB)
    parser.add_argument("--session-id", help="default: newest session with usage")
    parser.add_argument("--cwd", help="narrow to sessions run in this directory")
    args = parser.parse_args()
    usage = session_usage(args.db, args.session_id, args.cwd)
    json.dump(usage, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
