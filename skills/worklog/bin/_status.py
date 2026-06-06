#!/usr/bin/env python3
"""Standup-shaped summary from git log commits + task-file frontmatter.

Called by bin/status.sh with:
  argv: fmt author since focus_slug focus_project
  stdin: git log output (record-separated, see status.sh LOG_ARGS)
"""

import json
import pathlib
import re
import sys

STATUS_ORDER = ["shipping", "archived", "in-review", "blocked", "in-progress", "draft", "unknown"]
STATUS_LABEL = {
  "shipping": "shipping",
  "archived": "shipped / archived",
  "in-review": "in-review",
  "blocked": "blocked",
  "in-progress": "in-progress",
  "draft": "new / draft",
  "unknown": "(no status found)",
}

# Lifecycle buckets for the default standup view. Order here is also render order.
# Shipped is the "done" terminal; in-flight folds in-progress, shipping, draft,
# and unknown so a standup reader sees every actionable row without triaging
# granular status labels. Blocked gets its own bucket — it's the one state that
# needs someone else to move.
LIFECYCLE_BUCKETS = [
  ("shipped", "Shipped", {"archived"}),
  ("in_review", "In review", {"in-review"}),
  ("in_flight", "In flight", {"in-progress", "shipping", "draft", "unknown"}),
  ("blocked", "Blocked", {"blocked"}),
]


def _first_sentence(text: str) -> str:
  """Cap at the first sentence boundary — `.`, `!`, `?`, or a newline.
  Keeps the terminator so readers can tell it's a full sentence."""
  text = text.strip()
  if not text or text in {"|", "—", "-"}:
    return ""
  m = re.search(r"[.!?](?:\s|$)|\n", text)
  return text[:m.end()].strip() if m else text


def _pr_tag(prs: list[str]) -> str:
  if not prs:
    return ""
  return "#" + ", #".join(prs)


def _trailer(body: str, key: str) -> str:
  # [ \t]* not \s* — \s includes \n, which would eat the next line's content
  # when a trailer is empty (e.g. `Worklog-Linear:\n` followed by `Worklog-PR: ...`).
  m = re.search(rf"^{re.escape(key)}:[ \t]*(.*)$", body, re.MULTILINE)
  return m.group(1).strip() if m else ""


def parse_commits(raw: str) -> list[dict]:
  commits = []
  for record in raw.split("\x1e"):
    record = record.strip("\x00\n")
    if not record:
      continue
    parts = record.split("\x1f")
    if len(parts) < 2:
      continue
    sha, subject = parts[0], parts[1]
    body = parts[2] if len(parts) > 2 else ""
    slug_m = re.match(r"^([a-z0-9][a-z0-9-]*):", subject)
    slug = slug_m.group(1) if slug_m else None
    next_m = re.search(r"^next:\s*(.+?)$", body, re.MULTILINE)
    commits.append({
      "sha": sha[:7],
      "subject": subject,
      "slug": slug,
      "next": next_m.group(1).strip() if next_m else "",
      "status": _trailer(body, "Worklog-Status"),
      "kind": _trailer(body, "Worklog-Kind"),
      "linear": _trailer(body, "Worklog-Linear"),
      "pr": _trailer(body, "Worklog-PR"),
      "prev_slug": _trailer(body, "Worklog-Previous-Slug"),
    })
  return commits


def render_slug_history(commits: list[dict], focus_slug: str, fmt: str) -> None:
  if fmt == "json":
    print(json.dumps(commits, indent=2))
    return
  print(f"# {focus_slug} — history")
  for c in reversed(commits):
    line = f"- {c['sha']} {c['subject']}"
    if c["next"]:
      line += f"\n    → {c['next']}"
    if c["status"]:
      line += f"  [status={c['status']}]"
    print(line)


def read_frontmatter_field(author: str, slug: str, key: str) -> str:
  for sub in ("active", "archive"):
    p = pathlib.Path(f"people/{author}/{sub}/{slug}.md")
    if p.exists():
      m = re.search(rf"^{key}:[ \t]*(\S*)", p.read_text(), re.MULTILINE)
      if m:
        return m.group(1)
  return ""


def _current_field(by_slug: dict, author: str, slug: str, key: str) -> str:
  # Group by CURRENT status/project of each slug (from active/archive files),
  # not the last-seen trailer, because trailers are delta-only.
  value = read_frontmatter_field(author, slug, key)
  if value:
    return value
  for c in by_slug[slug]:
    if c["prev_slug"]:
      return _current_field(by_slug, author, c["prev_slug"], key)
  return ""


def _resolves_to_file(author: str, slug: str, by_slug: dict) -> bool:
  for sub in ("active", "archive"):
    if pathlib.Path(f"people/{author}/{sub}/{slug}.md").exists():
      return True
  for c in by_slug.get(slug, []):
    if c["prev_slug"] and _resolves_to_file(author, c["prev_slug"], by_slug):
      return True
  return False


def summarize(commits: list[dict], author: str, focus_project: str) -> dict:
  by_slug: dict = {}
  for c in commits:
    if not c["slug"]:
      continue
    by_slug.setdefault(c["slug"], []).append(c)

  items_by_slug = {}
  for slug, cs in by_slug.items():
    # Drop meta commits whose subject happens to look like `<slug>:` but don't
    # correspond to a real task file (e.g. `checkpoint: archive foo, update bar`).
    if not _resolves_to_file(author, slug, by_slug):
      continue
    st = _current_field(by_slug, author, slug, "status") or "unknown"
    proj = _current_field(by_slug, author, slug, "project")
    if focus_project and proj != focus_project:
      continue
    prs = set()
    for c in cs:
      for n in re.findall(r"\d+", c["pr"] or ""):
        prs.add(n)
    items_by_slug[slug] = {
      "slug": slug,
      "status": st,
      "project": proj,
      "next": next((c["next"] for c in cs if c["next"]), ""),
      "prs": sorted(prs, key=int),
      "headline": cs[0]["subject"],
      "kind": next((c["kind"] for c in cs if c["kind"]), ""),
      "linear": next((c["linear"] for c in cs if c["linear"]), ""),
      "commits": len(cs),
    }

  by_project: dict = {}
  for it in items_by_slug.values():
    by_project.setdefault(it["project"] or "(no project)", {}).setdefault(it["status"], []).append(it)
  return by_project


def _flat_items(by_project: dict) -> list[dict]:
  items = []
  for statuses in by_project.values():
    for group in statuses.values():
      items.extend(group)
  return items


def render_standup(by_project: dict, author: str, since: str, focus_project: str, fmt: str) -> None:
  """Default view. Groups by lifecycle bucket (shipped · in-review · in-flight ·
  blocked) so the reader sees the standup shape without triaging every status
  label. Project is a tag on each row; projects-touched appears once at the end."""
  if fmt == "json":
    print(json.dumps({
      "author": author, "since": since,
      "project_filter": focus_project or None,
      "projects": by_project,
    }, indent=2))
    return

  items = _flat_items(by_project)

  header = f"# {author} — standup since {since}"
  if focus_project:
    header += f"  ·  project: {focus_project}"
  print(header)
  print()
  if not items:
    print("_nothing to report_")
    return

  buckets = {key: [] for key, _, _ in LIFECYCLE_BUCKETS}
  for it in items:
    for key, _, statuses in LIFECYCLE_BUCKETS:
      if it["status"] in statuses:
        buckets[key].append(it)
        break

  for key, label, _ in LIFECYCLE_BUCKETS:
    rows = sorted(buckets[key], key=lambda x: x["slug"])
    if not rows:
      continue
    print(f"## {label} ({len(rows)})")
    if key == "shipped":
      parts = []
      for it in rows:
        pr = _pr_tag(it["prs"])
        parts.append(f"{it['slug']} ({pr})" if pr else it["slug"])
      print(" · ".join(parts))
    else:
      for it in rows:
        tags = []
        if it["prs"]:
          tags.append(_pr_tag(it["prs"]))
        if it["status"] == "shipping":
          tags.append("shipping")
        if it["project"]:
          tags.append(it["project"])
        tag_str = f" ({', '.join(tags)})" if tags else ""
        sentence = _first_sentence(it["next"])
        detail = f" — {sentence}" if sentence else ""
        print(f"- {it['slug']}{tag_str}{detail}")
    print()

  projects = sorted({it["project"] for it in items if it["project"] and it["project"] != "(no project)"})
  if projects:
    print("## Projects touched")
    print(" · ".join(projects))


def render_grouped(by_project: dict, author: str, since: str, focus_project: str, fmt: str) -> None:
  """Legacy per-project × per-status view. Kept behind --format=grouped for
  audits where seeing every archived task by project is the point."""
  if fmt == "json":
    print(json.dumps({
      "author": author, "since": since,
      "project_filter": focus_project or None,
      "projects": by_project,
    }, indent=2))
    return

  header = f"# {author} — worklog since {since}"
  if focus_project:
    header += f"  ·  project: {focus_project}"
  print(header)
  print()
  if not by_project:
    print("_nothing to report_")
    return

  for proj in sorted(by_project.keys(), key=lambda p: (p == "(no project)", p)):
    print(f"## {proj}")
    statuses = by_project[proj]
    for g in STATUS_ORDER:
      items = statuses.get(g) or []
      if not items:
        continue
      print(f"### {STATUS_LABEL[g]}")
      for it in sorted(items, key=lambda x: x["slug"]):
        meta = []
        if it["prs"]:
          meta.append("PR " + ", ".join(f"#{p}" for p in it["prs"]))
        if it["linear"]:
          meta.append(it["linear"])
        if it["kind"]:
          meta.append(it["kind"])
        meta_str = f"  _{' · '.join(meta)}_" if meta else ""
        print(f"- **{it['slug']}**{meta_str}")
        sentence = _first_sentence(it["next"])
        if sentence:
          print(f"    → {sentence}")
      print()


def main() -> None:
  fmt, author, since, focus_slug, focus_project = sys.argv[1:6]
  commits = parse_commits(sys.stdin.read())

  if focus_slug:
    render_slug_history(commits, focus_slug, fmt)
    return

  by_project = summarize(commits, author, focus_project)
  if fmt == "grouped":
    render_grouped(by_project, author, since, focus_project, "markdown")
  else:
    render_standup(by_project, author, since, focus_project, fmt)


if __name__ == "__main__":
  main()
