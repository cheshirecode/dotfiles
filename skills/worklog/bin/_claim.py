#!/usr/bin/env python3
"""Claim-block manipulation + arbitration for bin/project.sh (phase 2).

Subcommands (all operate on task files; no git ops here):

  read <path>
      Print JSON {has_claim, session_id, lock_at, heartbeat_at} for the
      task file's current `claim:` frontmatter block. Missing keys → null.

  write <path> --session=ID [--stale-after=30m]
      Insert/replace a `claim:` block in the file's frontmatter with
      session_id, lock_at=now, heartbeat_at=now. Refuses if there is an
      existing non-stale claim with a different session_id (unless
      --force is set).

  clear <path> [--session=ID]
      Remove the `claim:` block. If --session=ID is set, only clears
      when current claim matches (idempotent for owner / no-op for
      others).

  tick <path> --session=ID
      Update heartbeat_at=now in the file's claim block iff it's held
      by the given session_id. No-op otherwise.

  is-stale <path> --stale-after=30m
      Exit 0 if file has a claim and its heartbeat_at is older than
      <stale_after> (parsed `Ns|Nm|Nh|Nd`); exit 1 otherwise (no claim,
      or claim is fresh).

  arbitrate --staged=PATH --head=PATH --stale-after=DUR
      For pre-commit hook use. Both PATHs hold the full file contents
      (staged version + HEAD version). Exits:
        0 — no conflict (staged claim allowed)
        2 — conflict (HEAD has a non-stale claim with a different
            session_id than the staged version's claim)

  project-stale-after <project-slug>
      Print the project's mutex.stale_after value, or "30m" default.
      Exits 1 if the project slug doesn't resolve.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys

import yaml

FRONTMATTER_RE = re.compile(r"^(---\n)(.*?)(\n---\n)", re.DOTALL)


class FrontmatterDumper(yaml.SafeDumper):
  """Emit block sequences in the repo's yamllint-friendly frontmatter style."""

  def increase_indent(self, flow: bool = False, indentless: bool = False):
    return super().increase_indent(flow, False)


def _now_iso() -> str:
  return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_dur(s: str) -> int:
  """Parse `30m` / `2h` / `45s` / `1d` into seconds."""
  m = re.match(r"^\s*(\d+)\s*([smhd])\s*$", s)
  if not m:
    raise ValueError(f"bad duration: {s!r}")
  n = int(m.group(1))
  unit = m.group(2)
  return n * {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]


def _parse_iso(s: str) -> dt.datetime:
  if s.endswith("Z"):
    s = s[:-1] + "+00:00"
  return dt.datetime.fromisoformat(s)


def _read_frontmatter(path: pathlib.Path) -> tuple[str, dict, str]:
  """Return (prefix, fm_dict, suffix). prefix='---\\n', suffix='\\n---\\n…rest'."""
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    raise ValueError(f"{path}: no frontmatter")
  fm = yaml.safe_load(m.group(2)) or {}
  if not isinstance(fm, dict):
    raise ValueError(f"{path}: frontmatter not a mapping")
  return m.group(1), fm, m.group(3) + text[m.end():]


def _write_frontmatter(path: pathlib.Path, fm: dict, suffix: str) -> None:
  # yaml.safe_dump emits multi-line; preserve the rest of the file untouched.
  body = yaml.dump(
      fm,
      Dumper=FrontmatterDumper,
      sort_keys=False,
      default_flow_style=False,
  ).rstrip("\n")
  path.write_text("---\n" + body + suffix)


def _is_stale(claim: dict, stale_after_sec: int) -> bool:
  hb = claim.get("heartbeat_at") or claim.get("lock_at")
  if not hb:
    return True
  try:
    age = (dt.datetime.now(dt.timezone.utc) - _parse_iso(str(hb))).total_seconds()
  except Exception:
    return True
  return age > stale_after_sec


def cmd_read(args: argparse.Namespace) -> int:
  path = pathlib.Path(args.path)
  _, fm, _ = _read_frontmatter(path)
  c = fm.get("claim") or {}
  out = {
    "has_claim": bool(c),
    "session_id": c.get("session_id"),
    "lock_at": c.get("lock_at"),
    "heartbeat_at": c.get("heartbeat_at"),
  }
  # Enrich with session registration metadata if present (phase-3 LOCKED_BY
  # surfacing — host + started_at help humans disambiguate machine-UUID
  # sessions where the bare session_id is opaque).
  sid = c.get("session_id")
  if sid:
    safe = sid.replace(":", "_")
    reg = pathlib.Path(".cache/sessions") / f"{safe}.json"
    if reg.exists():
      try:
        meta = json.loads(reg.read_text())
        out["host"] = meta.get("host")
        out["started_at"] = meta.get("started_at")
        out["pid"] = meta.get("pid")
      except Exception:
        pass
  print(json.dumps(out))
  return 0


def cmd_write(args: argparse.Namespace) -> int:
  path = pathlib.Path(args.path)
  prefix, fm, suffix = _read_frontmatter(path)
  existing = fm.get("claim") or {}
  stale_sec = _parse_dur(args.stale_after)
  if existing and not args.force:
    if existing.get("session_id") != args.session and not _is_stale(existing, stale_sec):
      print(f"claim write: LOCKED_BY={existing.get('session_id')} "
            f"heartbeat={existing.get('heartbeat_at')}", file=sys.stderr)
      return 3
  now = _now_iso()
  fm["claim"] = {
    "session_id": args.session,
    "lock_at": existing.get("lock_at") if existing.get("session_id") == args.session else now,
    "heartbeat_at": now,
  }
  _write_frontmatter(path, fm, suffix)
  return 0


def cmd_clear(args: argparse.Namespace) -> int:
  path = pathlib.Path(args.path)
  _, fm, suffix = _read_frontmatter(path)
  c = fm.get("claim")
  if not c:
    return 0
  if args.session and c.get("session_id") != args.session:
    # Not ours — idempotent no-op.
    return 0
  fm.pop("claim", None)
  _write_frontmatter(path, fm, suffix)
  return 0


def cmd_tick(args: argparse.Namespace) -> int:
  path = pathlib.Path(args.path)
  _, fm, suffix = _read_frontmatter(path)
  c = fm.get("claim") or {}
  if c.get("session_id") != args.session:
    return 0  # not ours, no-op
  c["heartbeat_at"] = _now_iso()
  fm["claim"] = c
  _write_frontmatter(path, fm, suffix)
  return 0


def cmd_is_stale(args: argparse.Namespace) -> int:
  path = pathlib.Path(args.path)
  _, fm, _ = _read_frontmatter(path)
  c = fm.get("claim") or {}
  if not c:
    return 1
  return 0 if _is_stale(c, _parse_dur(args.stale_after)) else 1


def _claim_from_text(text: str) -> dict:
  m = FRONTMATTER_RE.match(text)
  if not m:
    return {}
  fm = yaml.safe_load(m.group(2)) or {}
  if not isinstance(fm, dict):
    return {}
  return fm.get("claim") or {}


def cmd_arbitrate(args: argparse.Namespace) -> int:
  """Pre-commit arbiter. Reads two file paths (staged + HEAD)."""
  staged = pathlib.Path(args.staged).read_text() if pathlib.Path(args.staged).exists() else ""
  head = pathlib.Path(args.head).read_text() if pathlib.Path(args.head).exists() else ""
  sc = _claim_from_text(staged)
  hc = _claim_from_text(head)
  if not hc:
    return 0  # nothing on HEAD to conflict with
  stale_sec = _parse_dur(args.stale_after)
  if _is_stale(hc, stale_sec):
    return 0  # HEAD's claim is stale; staged commit may reap/overwrite
  if not sc:
    # Staged removes the claim. Only OK if staged session is same as HEAD's
    # (release path) — otherwise it's a foreign clear.
    # For phase 2 simplicity, also allow when there's no claim at all on
    # staged AND HEAD claim is stale (reap path). We already handled stale.
    print(f"claim arbitrate: REJECT — staged commit clears non-stale claim "
          f"held by {hc.get('session_id')}", file=sys.stderr)
    return 2
  if sc.get("session_id") != hc.get("session_id"):
    print(f"claim arbitrate: REJECT — HEAD held by {hc.get('session_id')} "
          f"(heartbeat={hc.get('heartbeat_at')}); staged session is "
          f"{sc.get('session_id')}", file=sys.stderr)
    return 2
  return 0


def cmd_project_stale_after(args: argparse.Namespace) -> int:
  slug = args.slug
  for state in ("active", "archive"):
    for p in sorted(pathlib.Path("people").glob(f"*/{state}/{slug}.md")):
      _, fm, _ = _read_frontmatter(p)
      mutex = fm.get("mutex") or {}
      print(mutex.get("stale_after") or "30m")
      return 0
  print(f"project-stale-after: no task file for '{slug}'", file=sys.stderr)
  return 1


def main() -> None:
  ap = argparse.ArgumentParser()
  sub = ap.add_subparsers(dest="cmd", required=True)

  s = sub.add_parser("read")
  s.add_argument("path")
  s.set_defaults(fn=cmd_read)

  s = sub.add_parser("write")
  s.add_argument("path")
  s.add_argument("--session", required=True)
  s.add_argument("--stale-after", default="30m")
  s.add_argument("--force", action="store_true")
  s.set_defaults(fn=cmd_write)

  s = sub.add_parser("clear")
  s.add_argument("path")
  s.add_argument("--session", default=None)
  s.set_defaults(fn=cmd_clear)

  s = sub.add_parser("tick")
  s.add_argument("path")
  s.add_argument("--session", required=True)
  s.set_defaults(fn=cmd_tick)

  s = sub.add_parser("is-stale")
  s.add_argument("path")
  s.add_argument("--stale-after", default="30m")
  s.set_defaults(fn=cmd_is_stale)

  s = sub.add_parser("arbitrate")
  s.add_argument("--staged", required=True)
  s.add_argument("--head", required=True)
  s.add_argument("--stale-after", default="30m")
  s.set_defaults(fn=cmd_arbitrate)

  s = sub.add_parser("project-stale-after")
  s.add_argument("slug")
  s.set_defaults(fn=cmd_project_stale_after)

  args = ap.parse_args()
  sys.exit(args.fn(args))


if __name__ == "__main__":
  main()
