#!/usr/bin/env python3
"""Context-pack renderer for one task file.

Called by bin/context.sh with:
  argv: slug for_mode fmt file_path
  stdin: git log output (record-separated, see context.sh)
"""

import json
import pathlib
import re
import os
import subprocess
import sys

import yaml

# Repos to enrich PR data against. Format: "owner/repo" full strings.
# Source: $WORKLOG_KNOWN_REPOS env (comma-separated). Empty -> skip PR
# enrichment entirely (better than guessing the wrong org from a
# placeholder list — pre-Phase-2 the list was bootstrap-scrubbed to
# "cheshirecode/<repo>" placeholders that resolved to nonsense).
KNOWN_REPOS = tuple(
  r.strip() for r in os.environ.get("WORKLOG_KNOWN_REPOS", "").split(",") if r.strip()
)
FRONTMATTER_FIELDS = ("status", "project", "kind", "linear", "pr", "last_updated", "next_action")


def parse_task_file(text: str) -> tuple[dict, str]:
  match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
  if not match:
    return {}, text
  fm = yaml.safe_load(match.group(1)) or {}
  return fm if isinstance(fm, dict) else {}, match.group(2)


def next_section(body: str) -> str:
  """Return the current top-level `## Next` section body.

  Older checkpoint notes can contain historical `## Next` headings and
  checkboxes. Tracker hydration should mirror only the durable current plan,
  not every stale checklist ever written into the task body.
  """
  lines = body.splitlines()
  collected = []
  in_next = False

  for line in lines:
    if re.match(r"^##\s+Next\b", line):
      if in_next:
        break
      in_next = True
      continue
    if in_next and re.match(r"^##\s+", line):
      break
    if in_next:
      collected.append(line)

  return "\n".join(collected)


def parse_work_items(body: str) -> list[dict]:
  """Parse `- [ ]` / `- [x]` checkboxes, folding soft-wrapped continuation
  lines into the same bullet. A continuation line is indented further than
  the bullet marker and does not itself start a new bullet or heading."""
  items = []
  current = None
  bullet_re = re.compile(r"^(\s*)-\s*\[([ xX])\]\s+(.+?)\s*$")
  new_block_re = re.compile(r"^\s*(?:[-*#]|\d+\.)\s")
  for line in next_section(body).splitlines():
    m = bullet_re.match(line)
    if m:
      current = {
        "status": "done" if m.group(2).lower() == "x" else "open",
        "text": m.group(3),
        "_indent": len(m.group(1)) + 2,  # past "- "
      }
      items.append(current)
      continue
    if current is None:
      continue
    if not line.strip():
      current = None
      continue
    leading = len(line) - len(line.lstrip())
    if leading >= current["_indent"] and not new_block_re.match(line):
      current["text"] += " " + line.strip()
    else:
      current = None
  for it in items:
    it.pop("_indent", None)
  return items


def parse_commits(raw: str) -> list[dict]:
  commits = []
  for rec in raw.split("\x1e"):
    rec = rec.strip("\n")
    if not rec:
      continue
    parts = rec.split("\x1f")
    if len(parts) < 3:
      continue
    sha, date, subject = parts[0], parts[1], parts[2]
    cbody = parts[3] if len(parts) > 3 else ""
    nxt = re.search(r"^next:\s*(.+?)$", cbody, re.MULTILINE)
    commits.append({
      "sha": sha,
      "date": date,
      "subject": subject,
      "next": nxt.group(1).strip() if nxt else "",
    })
  return commits


def fetch_prs(pr_field) -> list[dict]:
  if pr_field is None:
    return []
  # pr_field can be a list (YAML list) or a string.
  if isinstance(pr_field, list):
    numbers = [str(n) for n in pr_field if str(n).isdigit()]
  else:
    numbers = re.findall(r"\d+", str(pr_field))
  prs = []
  for n in numbers:
    # Skip silently if no known repos configured — better than guessing org.
    for repo_full in KNOWN_REPOS:
      try:
        out = subprocess.run(
          ["gh", "pr", "view", n, "-R", repo_full,
           "--json", "number,title,state,url,isDraft,reviewDecision,mergedAt"],
          capture_output=True, text=True, timeout=10, check=True,
        ).stdout
        prs.append({"repo": repo_full, **json.loads(out)})
        break
      except Exception:
        continue
  return prs


def render_markdown(slug: str, for_mode: str, fm: dict, body: str,
                    commits: list, prs: list, work_items: list) -> None:
  if for_mode == "compact":
    open_items = [w["text"] for w in work_items if w["status"] == "open"]
    last_sha = commits[0]["sha"] if commits else "—"
    last_subject = commits[0]["subject"] if commits else "—"
    print(f"slug: {slug}")
    print(f"status: {fm.get('status', '—')}")
    print(f"last_updated: {fm.get('last_updated', '—')}")
    print(f"last_sha: {last_sha}  {last_subject}")
    print(f"next: {fm.get('next_action', '—')}")
    if open_items:
      print("open:")
      for t in open_items[:5]:
        print(f"  - {t}")
    return
  print(f"# {slug} — context ({for_mode})")
  print()
  print("## Frontmatter")
  for k in FRONTMATTER_FIELDS:
    if k in fm:
      print(f"- **{k}**: {fm[k]}")
  print()

  if prs:
    print("## PRs")
    for pr in prs:
      badges = [pr.get("state", "?")]
      if pr.get("isDraft"):
        badges.append("DRAFT")
      if pr.get("reviewDecision"):
        badges.append(pr["reviewDecision"])
      print(f"- **{pr['repo']}#{pr['number']}** [{' · '.join(badges)}] {pr.get('title', '')}")
      print(f"    {pr.get('url', '')}")
    print()

  if commits:
    print("## Recent commits")
    for c in commits[:5]:
      print(f"- {c['sha']} {c['date']} · {c['subject']}")
      if c["next"]:
        print(f"    → {c['next']}")
    print()

  if for_mode == "resume":
    print("## Next")
    print(fm.get("next_action", "—"))
    print()
    open_items = [w for w in work_items if w["status"] == "open"]
    if open_items:
      print("## Open work items")
      for w in open_items:
        print(f"- {w['text']}")
      print()
      # Tracker-ready snippet: each agent gets a copy/exec-friendly call.
      # Per AGENTS.md § In-session progress visibility (lines 106-135) and
      # docs/lessons.md top-of-2026-04 entry on TaskCreate drift, this is
      # MANDATORY when ≥3 unchecked items remain (single-step tasks exempt).
      if len(open_items) >= 3:
        print("## Tracker-ready snippet (MANDATORY hydration; ≥3 open items)")
        print()
        print("Run one block matching the active agent:")
        print()
        print("**Claude Code** — invoke for each item:")
        print("```")
        for w in open_items:
          # Keep the subject readable; full text in description.
          subject = w["text"][:60].rstrip()
          if subject != w["text"]:
            subject = subject + "…"
          print(f'TaskCreate(subject="{subject}", description="{w["text"]}", '
                f'metadata={{"slug": "{slug}"}})')
        print("```")
        print()
        print("**Codex CLI** — emit one `update_plan` call:")
        print("```")
        steps = [{"step": w["text"], "status": "pending"} for w in open_items]
        print(f"update_plan(plan={steps!r})")
        print("```")
        print()
        print("**Cursor** — populate canvas todo card / Plan Mode entries with the open items above.")
        print()
        print("Skip only if every item is single-step / trivial. Don't wait for the user to ask.")
      else:
        print("## Tracker hint")
        print(f"Only {len(open_items)} open item(s) — tracker hydration optional. "
              "Mirror to `TaskCreate` / `update_plan` / Cursor todos if useful.")
      print()
    print("## Body")
    print(body.rstrip())
  elif for_mode == "review":
    review_body = re.sub(r"## Invariants.*?(?=\n## |\Z)", "", body, flags=re.DOTALL)
    print("## Task body (review-relevant)")
    print(review_body.rstrip())


def main() -> None:
  slug, for_mode, fmt, file_path = sys.argv[1:5]
  text = pathlib.Path(file_path).read_text()
  fm, body = parse_task_file(text)
  work_items = parse_work_items(body)
  commits = parse_commits(sys.stdin.read())
  prs = fetch_prs(fm.get("pr"))

  if fmt == "json":
    print(json.dumps({
      "slug": slug, "mode": for_mode, "frontmatter": fm,
      "commits": commits, "prs": prs, "work_items": work_items,
      "body": body,
    }, indent=2, default=str))
    return

  render_markdown(slug, for_mode, fm, body, commits, prs, work_items)


if __name__ == "__main__":
  main()
