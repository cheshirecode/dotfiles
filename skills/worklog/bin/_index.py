#!/usr/bin/env python3
"""Build a JSONL index of every task file under people/*/{active,archive}/.

Called by bin/index.sh. Emits one JSON object per line on stdout:

  {slug, ldap, state, file, kind, status, project, linear, pr, repos,
   parent_slug, related, supersedes, superseded_by, reopens,
   last_updated, size_bytes, body_refs: {prs, linear, slugs}}

Index is a derivative — never committed. Derived queries (children.sh,
pr.sh, stale.sh) read it to answer cross-reference questions without
rescanning the corpus.

Strict YAML only — frontmatter that fails to parse is treated as an empty
mapping and its record degrades gracefully. bin/lint.sh is the canonical
detector for malformed frontmatter; fix parse errors there.
"""

from __future__ import annotations

import json
import pathlib
import re
from typing import Any

import yaml

ENG_RE = re.compile(r"\bENG-\d+\b")
PR_RE = re.compile(r"(?:^|[^A-Za-z0-9_])#(\d{2,6})\b")
SLUG_MENTION_RE = re.compile(r"\b(?:eng-\d+-)?[a-z][a-z0-9]*(?:-[a-z0-9]+){1,5}\b")

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n(.*)$", re.DOTALL)


def parse_task_file(path: pathlib.Path) -> tuple[dict[str, Any], str]:
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    return {}, text
  try:
    fm = yaml.safe_load(m.group(1)) or {}
    if not isinstance(fm, dict):
      fm = {}
  except yaml.YAMLError:
    # Malformed frontmatter — bin/lint.sh flags this separately; degrade
    # gracefully here so a single broken file doesn't corrupt the index.
    fm = {}
  return fm, m.group(2)


def _ensure_list(value: Any) -> list[Any]:
  if value is None:
    return []
  if isinstance(value, list):
    return value
  return [value]


def _parse_pr_numbers(value: Any) -> list[int]:
  nums: set[int] = set()
  for item in _ensure_list(value):
    if isinstance(item, int):
      nums.add(item)
      continue
    for m in re.findall(r"\d+", str(item)):
      nums.add(int(m))
  return sorted(nums)


def _normalize_related(value: Any) -> list[dict[str, str]]:
  out: list[dict[str, str]] = []
  for item in _ensure_list(value):
    if isinstance(item, dict) and "slug" in item:
      out.append({"slug": str(item["slug"]), "note": str(item.get("note") or "")})
  return out


def _scan_body_refs(body: str, known_slugs: set[str]) -> dict[str, list[Any]]:
  prs = sorted({int(m) for m in PR_RE.findall(body)})
  linear = sorted(set(ENG_RE.findall(body)))
  slugs = sorted({m for m in SLUG_MENTION_RE.findall(body) if m in known_slugs})
  return {"prs": prs, "linear": linear, "slugs": slugs}


def _collect_tasks(root: pathlib.Path) -> list[tuple[pathlib.Path, str, str, dict[str, Any], str]]:
  """Return (path, ldap, state, frontmatter, body) for every task file."""
  tasks = []
  for ldap_dir in sorted((root / "people").glob("*")):
    if not ldap_dir.is_dir():
      continue
    ldap = ldap_dir.name
    for state in ("active", "archive"):
      state_dir = ldap_dir / state
      if not state_dir.is_dir():
        continue
      for path in sorted(state_dir.glob("*.md")):
        fm, body = parse_task_file(path)
        tasks.append((path, ldap, state, fm, body))
  return tasks


def build_record(
  path: pathlib.Path,
  ldap: str,
  state: str,
  fm: dict[str, Any],
  body: str,
  known_slugs: set[str],
) -> dict[str, Any]:
  slug = str(fm.get("slug") or path.stem)
  return {
    "slug": slug,
    "ldap": ldap,
    "state": state,
    "file": str(path),
    "kind": str(fm.get("kind") or ""),
    "status": str(fm.get("status") or ""),
    "project": str(fm.get("project") or ""),
    "linear": str(fm.get("linear") or ""),
    "pr": _parse_pr_numbers(fm.get("pr")),
    "repos": [str(r) for r in _ensure_list(fm.get("repos"))],
    "parent_slug": str(fm.get("parent_slug") or ""),
    "related": _normalize_related(fm.get("related")),
    "supersedes": str(fm.get("supersedes") or ""),
    "superseded_by": str(fm.get("superseded_by") or ""),
    "reopens": str(fm.get("reopens") or ""),
    "last_updated": str(fm.get("last_updated") or ""),
    "size_bytes": path.stat().st_size,
    "body_refs": _scan_body_refs(body, known_slugs),
  }


def main() -> None:
  root = pathlib.Path.cwd()
  raw = _collect_tasks(root)
  known_slugs = {str(fm.get("slug") or path.stem) for path, _, _, fm, _ in raw}
  for path, ldap, state, fm, body in raw:
    record = build_record(path, ldap, state, fm, body, known_slugs)
    print(json.dumps(record, ensure_ascii=False))


if __name__ == "__main__":
  main()
