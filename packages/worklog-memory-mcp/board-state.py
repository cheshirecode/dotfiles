"""Read board cards through Worklog's canonical YAML parser; never write task data."""
import json
import re
from pathlib import Path
import sys

repo, ldap, helpers = sys.argv[1:]
sys.path.insert(0, helpers)
from _index import parse_task_file  # noqa: E402

root = Path(repo) / "people" / ldap
tasks = []
archived = list((root / "archive").glob("*.md"))
recent = sorted(archived, key=lambda p: p.stat().st_mtime, reverse=True)[:50]
for file in [*sorted((root / "active").glob("*.md")), *recent]:
    if file.is_symlink():
        continue
    fm, body = parse_task_file(file)
    context = re.search(r"^## Context\s*\n(.*?)(?=^## |\Z)", body, re.M | re.S)
    content = context.group(1) if context else body
    lines = [line.strip() for line in content.splitlines()
             if line.strip() and not line.startswith(("#", "Archived ", "---"))]
    slug = file.stem
    tasks.append({
        "slug": slug, "title": str(fm.get("title") or (lines[0] if lines else slug.replace("-", " ")))[:180],
        "status": str(fm.get("status") or "draft"), "kind": str(fm.get("kind") or "task"),
        "project": str(fm.get("project") or "none"), "next_action": str(fm.get("next_action") or ""),
        "updated": str(fm.get("last_updated") or ""), "claim": fm.get("claim") or {},
        "body": body[:100000], "archived": file.parent.name == "archive",
    })
print(json.dumps({"tasks": tasks, "archived_total": len(archived)}, default=str))
