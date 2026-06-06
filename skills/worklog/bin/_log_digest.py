#!/usr/bin/env python3
"""Burst-folding digest of git log. Read-time projection only — never
rewrites history. See bin/log-digest.sh for the CLI wrapper.

A "burst" is a run of ≥min-burst consecutive same-slug commits whose
subject matches `<slug>: checkpoint$`, with each pair within
--burst-window seconds. Status/create/archive commits split bursts.

Stdin: `git log --format='%H%x1f%ct%x1f%s%x1f%b%x1e' [filters]`.
Stdout: markdown (default) or JSON digest.
"""
from __future__ import annotations

import datetime
import json
import re
import sys

CHECKPOINT_RE = re.compile(r"^([a-z][a-z0-9-]+):\s+checkpoint\s*$")
SLUG_RE = re.compile(r"^([a-z][a-z0-9-]+):")
NEXT_RE = re.compile(r"^next:\s*(.+)$", re.MULTILINE)


def parse_log(stream: str) -> list[dict]:
  out: list[dict] = []
  for raw in stream.split("\x1e"):
    raw = raw.strip("\n")
    if not raw:
      continue
    parts = raw.split("\x1f", 3)
    if len(parts) < 4:
      continue
    sha, ct, subject, body = parts
    out.append({
      "sha": sha[:8],
      "time": int(ct),
      "subject": subject,
      "body": body,
    })
  return out


def slug_of(subject: str) -> str | None:
  m = SLUG_RE.match(subject)
  return m.group(1) if m else None


def fold(commits: list[dict], min_burst: int, window: int) -> list[dict]:
  """Walk commits oldest→newest; emit list of {kind: 'commit'|'burst', ...}."""
  out: list[dict] = []
  cur: list[dict] = []
  cur_slug: str | None = None

  def flush() -> None:
    nonlocal cur, cur_slug
    if not cur:
      return
    if len(cur) >= min_burst:
      out.append({
        "kind": "burst",
        "slug": cur_slug,
        "count": len(cur),
        "first_time": cur[0]["time"],
        "last_time": cur[-1]["time"],
        "first_sha": cur[0]["sha"],
        "last_sha": cur[-1]["sha"],
        "next_actions": [
          (m.group(1).strip() if (m := NEXT_RE.search(c["body"])) else "")
          for c in cur
        ],
      })
    else:
      for c in cur:
        out.append({"kind": "commit", **c})
    cur = []
    cur_slug = None

  for c in commits:
    is_ckpt = bool(CHECKPOINT_RE.match(c["subject"]))
    s = slug_of(c["subject"]) if is_ckpt else None
    if (
      is_ckpt and s == cur_slug
      and cur and (c["time"] - cur[-1]["time"]) <= window
    ):
      cur.append(c)
    else:
      flush()
      if is_ckpt:
        cur = [c]
        cur_slug = s
      else:
        out.append({"kind": "commit", **c})
  flush()
  return out


def fmt_time(epoch: int) -> str:
  return datetime.datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M")


def render_md(items: list[dict], obsidian: bool) -> str:
  def slug_link(s: str) -> str:
    return f"[[{s}]]" if obsidian else s

  lines: list[str] = []
  for item in items:
    if item["kind"] == "commit":
      ts = fmt_time(item["time"])
      lines.append(f"- {item['sha']} [{ts}] {item['subject']}")
    else:
      first = fmt_time(item["first_time"])
      last = fmt_time(item["last_time"])
      lines.append(
        f"- **burst** {slug_link(item['slug'])} × {item['count']} "
        f"({first} → {last}, {item['first_sha']}…{item['last_sha']})"
      )
      seen = set()
      for na in item["next_actions"]:
        if not na or na in seen:
          continue
        seen.add(na)
        if len(na) > 200:
          na = na[:200].rstrip() + "…"
        lines.append(f"    - next: {na}")
  return "\n".join(lines) + "\n"


def main() -> None:
  min_burst = 3
  window = 4 * 3600  # seconds
  fmt = "md"
  obsidian = False
  for arg in sys.argv[1:]:
    if arg.startswith("--min-burst="):
      min_burst = int(arg.split("=", 1)[1])
    elif arg.startswith("--burst-window="):
      window = int(arg.split("=", 1)[1])
    elif arg.startswith("--format="):
      fmt = arg.split("=", 1)[1]
    elif arg == "--obsidian-links":
      obsidian = True
    else:
      print(f"_log_digest: unknown arg: {arg}", file=sys.stderr)
      sys.exit(2)

  commits = parse_log(sys.stdin.read())
  # Walk oldest→newest; git log default is newest-first, so reverse.
  commits.reverse()
  items = fold(commits, min_burst=min_burst, window=window)

  if fmt == "json":
    print(json.dumps(items, indent=2))
  else:
    print(render_md(items, obsidian=obsidian))


if __name__ == "__main__":
  main()
