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

from _task_context import make_kernel, kernel_markdown, parse_task_file, parse_work_items

# Repos to enrich PR data against. Format: "owner/repo" full strings.
# Source: WORKLOG_KNOWN_REPOS resolves short task repo names; explicit
# pr_repos mappings and exact body links need no global repository list.
KNOWN_REPOS = tuple(
  r.strip() for r in os.environ.get("WORKLOG_KNOWN_REPOS", "").split(",") if r.strip()
)
FRONTMATTER_FIELDS = ("status", "project", "kind", "linear", "pr", "last_updated", "next_action")


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


def pr_candidates(number, fm, body):
  mapping = fm.get("pr_repos") or {}
  explicit = (mapping.get(number) or mapping.get(str(number))) if isinstance(mapping, dict) else None
  if explicit:
    return [str(explicit)]
  linked = re.findall(r"https://github\.com/([^/\s]+/[^/\s]+)/pull/" + str(number) + r"(?:\b|/)", body)
  if linked:
    return list(dict.fromkeys(linked))
  candidates = []
  repos = fm.get("repos") or []
  for repo in repos if isinstance(repos, list) else []:
    if not isinstance(repo, str):
      continue
    if "/" in repo:
      candidates.append(repo)
    else:
      candidates.extend(known for known in KNOWN_REPOS if known.rsplit("/", 1)[-1] == repo)
  return list(dict.fromkeys(candidates))


def fetch_prs(pr_field, fm, body):
  # Frontmatter is a cached task association, not authoritative PR linkage.
  values = pr_field if isinstance(pr_field, list) else [pr_field]
  numbers = list(dict.fromkeys(int(v) for v in values if not isinstance(v, bool) and str(v).isdigit()))
  prs, diagnostics = [], []
  for number in numbers:
    candidates = pr_candidates(number, fm, body)
    if len(candidates) != 1:
      diagnostics.append({"number":number, "status":"ambiguous" if candidates else "unavailable",
                          "reason":"set pr_repos to one repository"})
      continue
    repo = candidates[0]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
      diagnostics.append({"number":number,"status":"unavailable","reason":"invalid repository mapping"})
      continue
    try:
      proc = subprocess.run(["gh", "pr", "view", str(number), "-R", repo, "--json",
                             "number,title,state,url,isDraft,reviewDecision,mergedAt"],
                            capture_output=True, text=True, timeout=10, check=True)
      data = json.loads(proc.stdout)
      if (not isinstance(data, dict) or type(data.get("number")) is not int or data["number"] != number
          or data.get("state") not in ("OPEN", "CLOSED", "MERGED")
          or not isinstance(data.get("url"), str)
          or data["url"].rstrip("/").lower() != f"https://github.com/{repo}/pull/{number}".lower()):
        raise ValueError("invalid PR response")
      prs.append({"repo":repo, **data})
    except subprocess.TimeoutExpired:
      diagnostics.append({"number":number,"status":"unavailable","reason":"query timed out"})
    except (OSError, ValueError, subprocess.CalledProcessError):
      diagnostics.append({"number":number,"status":"unavailable","reason":"query failed or returned invalid data"})
  return prs, diagnostics


def render_markdown(slug: str, for_mode: str, fm: dict, body: str,
                    commits: list, prs: list, work_items: list, tracker="none", diagnostics=()) -> None:
  print(f"# {slug} — context ({for_mode})")
  print()
  print("## Frontmatter")
  for k in FRONTMATTER_FIELDS:
    if k in fm:
      print(f"- **{k}**: {fm[k]}")
  print()

  if prs:
    print("## PRs (cached task links; live state)")
    for pr in prs:
      badges = [pr.get("state", "?")]
      if pr.get("isDraft"):
        badges.append("DRAFT")
      if pr.get("reviewDecision"):
        badges.append(pr["reviewDecision"])
      print(f"- **{pr['repo']}#{pr['number']}** [{' · '.join(badges)}] {pr.get('title', '')}")
      print(f"    {pr.get('url', '')}")
    print()

  if diagnostics:
    print("## PR enrichment")
    for item in diagnostics:
      print(f"- #{item['number']}: {item['status']} — {item['reason']}")
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
    if open_items and tracker != "none":
      print("## Tracker-ready snippet")
      print("Verify before hydrating: these items come from the current `## Next`, unchecked. "
            "Verify linked work, drop completed items, and hydrate only surviving items.")
      if len(open_items) < 3:
        print("Fewer than three items: tracker hydration is optional.")
      if tracker in ("claude", "all"):
        print("```text")
        for w in open_items:
          args = {"subject":w["text"][:60], "description":w["text"], "metadata":{"slug":slug}}
          print("TaskCreate(" + json.dumps(args, ensure_ascii=False) + ")")
        print("```")
      if tracker in ("codex", "all"):
        steps = [{"step":w["text"], "status":"pending"} for w in open_items]
        print("```text\nupdate_plan(" + json.dumps({"plan":steps}, ensure_ascii=False) + ")\n```")
      if tracker in ("cursor", "all"):
        print("Mirror verified open items from the task body into Cursor's tracker.")
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
  tracker = sys.argv[5] if len(sys.argv) > 5 else "none"
  if for_mode == "compact":
    last = commits[0] if commits else {}
    kernel = make_kernel(slug, fm, body, text, file_path, last.get("sha", ""), last.get("subject", ""))
    print(json.dumps(kernel, ensure_ascii=False) if fmt == "json" else kernel_markdown(kernel))
    return
  prs, diagnostics = fetch_prs(fm.get("pr"), fm, body)

  if fmt == "json":
    print(json.dumps({
      "slug": slug, "mode": for_mode, "frontmatter": fm,
      "commits": commits, "prs": prs, "work_items": work_items,
      "body": body, "pr_diagnostics": diagnostics, "pr_linkage": "frontmatter-cache",
    }, indent=2, default=str))
    return

  render_markdown(slug, for_mode, fm, body, commits, prs, work_items, tracker, diagnostics)


if __name__ == "__main__":
  main()
