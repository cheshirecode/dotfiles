#!/usr/bin/env python3
"""Watermark-filtered append-mode transcript dumper.

Reads the Claude Code JSONL transcript for the current session, filters to
messages with timestamp > mtime(out_file), runs the rest through
bin/_transcript_to_markdown.py, and appends a `## Session <id> — <trigger>
@ <ts>` section to `people/$LDAP/transcripts/<slug>.md`.

Env contract:
  CLAUDE_CODE_SESSION_ID   Session id; used to resolve the JSONL path under
                           ~/.claude/projects/<sanitized-cwd>/<id>.jsonl.
  WORKLOG_TRANSCRIPT_JSONL Optional override (test-friendly): if set, read
                           this path directly instead of resolving.
  WORKLOG_NO_TRANSCRIPT=1  Bypass; exit 0 without writing.
  LDAP                     Resolved LDAP (passed in by the caller).
  SLUG                     Target slug.
  TRIGGER                  Trigger event label (e.g. "manual", "archive",
                           "status:in-review").

Silent skip (exit 0) when CLAUDE_CODE_SESSION_ID + WORKLOG_TRANSCRIPT_JSONL
are both unset, when the JSONL path doesn't exist, or when
WORKLOG_NO_TRANSCRIPT=1.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys


def resolve_jsonl_path() -> pathlib.Path | None:
  override = os.environ.get("WORKLOG_TRANSCRIPT_JSONL")
  if override:
    p = pathlib.Path(override)
    return p if p.exists() else None
  session = os.environ.get("CLAUDE_CODE_SESSION_ID")
  if not session:
    return None
  # Claude Code sanitizes the cwd path into a directory name by replacing
  # EVERY non-alphanumeric char with '-' — not just '/'. The 2026-05-13 ship
  # regressed by only replacing '/', which produced …-projects-_worklog
  # vs. Claude's actual …-projects--worklog (the underscore was also '-'d).
  # Verified against the live path observed in the 2026-05-14 dry-run.
  cwd = pathlib.Path.cwd().resolve()
  sanitized = re.sub(r"[^a-zA-Z0-9]", "-", str(cwd))
  candidate = pathlib.Path.home() / ".claude" / "projects" / sanitized / f"{session}.jsonl"
  return candidate if candidate.exists() else None


def parse_ts(s: str) -> dt.datetime | None:
  if not s:
    return None
  try:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
  except (ValueError, AttributeError):
    return None


def filter_jsonl(src: pathlib.Path, watermark: dt.datetime | None) -> str:
  """Return a JSONL string containing only entries with ts > watermark."""
  out_lines: list[str] = []
  for raw in src.read_text().splitlines():
    raw = raw.strip()
    if not raw:
      continue
    try:
      entry = json.loads(raw)
    except json.JSONDecodeError:
      continue
    if watermark is not None:
      ts = parse_ts(entry.get("timestamp", ""))
      if ts is None or ts <= watermark:
        continue
    out_lines.append(raw)
  return "\n".join(out_lines) + ("\n" if out_lines else "")


def main() -> None:
  if os.environ.get("WORKLOG_NO_TRANSCRIPT") == "1":
    sys.exit(0)

  slug = os.environ.get("SLUG", "").strip()
  ldap = os.environ.get("LDAP", "").strip()
  trigger = os.environ.get("TRIGGER", "manual").strip()
  if not slug or not ldap:
    print("_dump_transcript: SLUG and LDAP required", file=sys.stderr)
    sys.exit(2)

  jsonl = resolve_jsonl_path()
  if jsonl is None:
    sys.exit(0)  # silent skip — no session JSONL available

  out_dir = pathlib.Path("people") / ldap / "transcripts"
  out_path = out_dir / f"{slug}.md"

  # Watermark: mtime of existing transcript file (if present), as UTC.
  watermark: dt.datetime | None = None
  if out_path.exists():
    watermark = dt.datetime.fromtimestamp(
      out_path.stat().st_mtime, tz=dt.timezone.utc
    )

  # Stage the filtered slice in a tempfile and feed it to the verbatim cheshirecode/<repo>
  # converter. (Don't reimplement conversion — `_transcript_to_markdown.py`
  # is copied from cheshirecode/<repo>/.claude/hooks/ verbatim per the design.)
  filtered = filter_jsonl(jsonl, watermark)
  if not filtered.strip():
    sys.exit(0)  # nothing new since last dump

  scratch = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"transcript-{slug}-{os.getpid()}.jsonl"
  scratch.write_text(filtered)
  try:
    converter = pathlib.Path(__file__).parent / "_transcript_to_markdown.py"
    proc = subprocess.run(
      [sys.executable, str(converter), str(scratch)],
      capture_output=True, text=True, check=True,
    )
    converted_body = proc.stdout
  except subprocess.CalledProcessError as e:
    print(f"_dump_transcript: converter failed: {e.stderr}", file=sys.stderr)
    sys.exit(1)
  finally:
    scratch.unlink(missing_ok=True)

  # The verbatim converter emits its own `# Claude Code Session: <slug>`
  # header with an empty slug (Claude's JSONL has no worklog-slug field —
  # confirmed by 2026-05-14 dry-run). Strip that header line; our wrapper
  # owns the file-level `# Slug:` and the per-section header.
  converted_body = re.sub(
    r"^# Claude Code Session:.*?\n(?:- \*\*[^\n]*\n)*\n?---\n+",
    "", converted_body, count=1, flags=re.DOTALL,
  )
  converted_body = converted_body.strip()
  if not converted_body:
    sys.exit(0)

  now_iso = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  session_id = os.environ.get("CLAUDE_CODE_SESSION_ID", "manual")

  out_dir.mkdir(parents=True, exist_ok=True)
  is_new = not out_path.exists()
  with out_path.open("a") as f:
    if is_new:
      f.write(f"# Slug: {slug}\n\n")
      f.write(
        "Auto-generated transcript log. Append-only per trigger event. "
        "Manual dumps via `bin/transcript-dump.sh <slug>`. "
        "Bypass via `WORKLOG_NO_TRANSCRIPT=1`.\n\n"
      )
    f.write(f"## Session {session_id} — {trigger} @ {now_iso}\n\n")
    f.write(converted_body)
    f.write("\n\n")


if __name__ == "__main__":
  main()
