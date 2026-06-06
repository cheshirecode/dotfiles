#!/usr/bin/env python3
"""Burst-detection + plan/sidecar emitter for bin/log-compact.sh.

Reads `git log` records from stdin (separator-encoded), groups same-slug
`<slug>: checkpoint` commits into bursts within --burst-window, and writes:
  - a markdown plan file (human-readable; review before --apply)
  - a sidecar TSV (machine-readable; consumed by the filter-repo step)

Stdin format (one record per commit, records separated by 0x1e, fields by 0x1f):
  <sha> 0x1f <iso8601> 0x1f <author> 0x1f <subject> 0x1f <body> 0x1e

Usage:
  git log ... | bin/_log_compact.py <slug> <keyword> <window-sec> <min-burst> <plan-path> <sidecar-path>
"""

import re
import sys
from datetime import datetime


ELIG_RE = re.compile(r"^([a-z0-9][a-z0-9-]*): checkpoint$")


def main() -> int:
  slug_filter = sys.argv[1]
  keyword_filter = sys.argv[2]
  window_sec = int(sys.argv[3])
  min_burst = int(sys.argv[4])
  plan_file = sys.argv[5]
  sidecar_file = sys.argv[6]

  keyword_re = re.compile(keyword_filter) if keyword_filter else None

  raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
  records = [r for r in raw.split("\x1e") if r.strip()]
  commits = []
  for r in records:
    parts = r.strip("\n").split("\x1f")
    if len(parts) < 4:
      continue
    sha, iso, author, subject = parts[0], parts[1], parts[2], parts[3]
    body = parts[4] if len(parts) > 4 else ""
    try:
      ts = datetime.fromisoformat(iso).timestamp()
    except ValueError:
      continue
    commits.append({
      "sha": sha, "iso": iso, "author": author,
      "subject": subject, "body": body, "ts": ts,
    })

  def slug_of(c):
    m = ELIG_RE.match(c["subject"])
    return m.group(1) if m else None

  def passes(c):
    s = slug_of(c)
    if s is None:
      return False
    if slug_filter and s != slug_filter:
      return False
    if keyword_re and not keyword_re.search(c["body"]):
      return False
    return True

  bursts = []
  current = []
  for c in commits:
    if not passes(c):
      if len(current) >= min_burst:
        bursts.append(current)
      current = []
      continue
    s = slug_of(c)
    if (current
        and slug_of(current[-1]) == s
        and current[-1]["author"] == c["author"]
        and (c["ts"] - current[-1]["ts"]) <= window_sec):
      current.append(c)
    else:
      if len(current) >= min_burst:
        bursts.append(current)
      current = [c]
  if len(current) >= min_burst:
    bursts.append(current)

  plan_lines = [
    f"# log-compact plan ({len(bursts)} burst(s) → "
    f"{sum(len(b) for b in bursts)} commit(s) compacted)",
    "",
    f"- filters: slug={slug_filter or 'any'}  keyword={keyword_filter or 'any'}  "
    f"window={window_sec}s  min-burst={min_burst}",
    "- run with `--apply` to rewrite history; tag `pre-compact-<ts>` will preserve "
    "original SHAs.",
    "",
  ]
  sidecar_lines = []
  for i, burst in enumerate(bursts, 1):
    s = slug_of(burst[0])
    first_iso = burst[0]["iso"][:10]
    last_iso = burst[-1]["iso"][:10]
    span = first_iso if first_iso == last_iso else f"{first_iso}..{last_iso}"
    new_subject = f"{s}: compacted {len(burst)} checkpoints ({span})"
    plan_lines.append(f"## Burst {i}: {new_subject}")
    plan_lines.append("")
    plan_lines.append(f"- {len(burst)} commits squashed into 1")
    plan_lines.append(f"- author: {burst[0]['author']}")
    plan_lines.append(f"- range: {burst[0]['sha'][:8]}..{burst[-1]['sha'][:8]}")
    plan_lines.append("")
    plan_lines.append("**Compacted body preview:**")
    plan_lines.append("")
    plan_lines.append("```")
    plan_lines.append(
      f"Compacted {len(burst)} original checkpoints into one. Iteration history below"
    )
    plan_lines.append("is the chronological sequence of next_action values across the burst.")
    plan_lines.append("")
    for c in burst:
      next_line = ""
      for ln in c["body"].splitlines():
        if ln.startswith("next: "):
          next_line = ln[len("next: "):].strip()
          break
      if not next_line:
        for ln in c["body"].splitlines():
          if ln.strip():
            next_line = ln.strip()
            break
      plan_lines.append(
        f"- {c['iso'][:16].replace('T', ' ')}  {next_line[:100]}"
      )
    plan_lines.append("")
    plan_lines.append(
      "Original SHAs (preserved at refs/tags/pre-compact-<timestamp>):"
    )
    for c in burst:
      plan_lines.append(f"  {c['sha']}")
    plan_lines.append("```")
    plan_lines.append("")
    for c in burst:
      sidecar_lines.append(f"{c['sha']}\t{burst[0]['sha']}\t{new_subject}")

  with open(plan_file, "w") as f:
    f.write("\n".join(plan_lines) + "\n")
  with open(sidecar_file, "w") as f:
    f.write("\n".join(sidecar_lines) + ("\n" if sidecar_lines else ""))

  print(f"plan: {plan_file}")
  print(f"sidecar: {sidecar_file}")
  print(
    f"bursts: {len(bursts)}  commits-to-squash: {sum(len(b) for b in bursts)}"
  )
  return 0


if __name__ == "__main__":
  sys.exit(main())
