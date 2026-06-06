#!/usr/bin/env python3
"""Emit exact external-scan seeds for `/worklog init --full`.

Called by bin/init-scan.sh with:
  argv: ldap format
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

import yaml

ENG_RE = re.compile(r"\bENG-\d+\b")
SLUG_ENG_RE = re.compile(r"^eng-(\d+)-")
NOTION_URL_RE = re.compile(r"https://www\.notion\.so/[^\s)>]+")
LINEAR_URL_RE = re.compile(r"https://linear\.app/[^\s)>]+")


def parse_task_file(path: pathlib.Path) -> tuple[dict[str, Any], str]:
  text = path.read_text()
  match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
  if not match:
    return {}, text
  raw_frontmatter = match.group(1)
  try:
    frontmatter = yaml.safe_load(raw_frontmatter) or {}
    if not isinstance(frontmatter, dict):
      frontmatter = {}
  except yaml.YAMLError:
    frontmatter = parse_frontmatter_fallback(raw_frontmatter)
  return frontmatter, match.group(2)


def parse_frontmatter_fallback(raw_frontmatter: str) -> dict[str, Any]:
  frontmatter: dict[str, Any] = {}
  current_key = ""
  for line in raw_frontmatter.splitlines():
    if not line.strip():
      continue
    if line.startswith(" ") and current_key:
      frontmatter[current_key] = f"{frontmatter[current_key]} {line.strip()}".strip()
      continue
    if ":" not in line:
      continue
    key, value = line.split(":", 1)
    current_key = key.strip()
    frontmatter[current_key] = value.strip()
  return frontmatter


def ensure_list(value: Any) -> list[Any]:
  if value is None:
    return []
  if isinstance(value, list):
    return value
  return [value]


def parse_pr_numbers(value: Any) -> list[int]:
  numbers: set[int] = set()
  for item in ensure_list(value):
    if isinstance(item, int):
      numbers.add(item)
      continue
    for match in re.findall(r"\d+", str(item)):
      numbers.add(int(match))
  return sorted(numbers)


def parse_primary_linear(slug: str, frontmatter_linear: Any) -> str | None:
  raw = str(frontmatter_linear or "").strip()
  if ENG_RE.fullmatch(raw):
    return raw
  slug_match = SLUG_ENG_RE.match(slug)
  if slug_match:
    return f"ENG-{slug_match.group(1)}"
  return None


def unique_preserve_order(items: list[str]) -> list[str]:
  seen: set[str] = set()
  ordered: list[str] = []
  for item in items:
    if not item or item in seen:
      continue
    seen.add(item)
    ordered.append(item)
  return ordered


def normalize_target(value: str) -> str:
  return value.strip().rstrip(".,)")


def extract_notion_targets(frontmatter: dict[str, Any], body: str) -> list[str]:
  targets: list[str] = []
  notion_value = frontmatter.get("notion")
  if notion_value:
    targets.append(normalize_target(str(notion_value)))

  external_refs = frontmatter.get("external_refs")
  if isinstance(external_refs, list):
    for ref in external_refs:
      if not isinstance(ref, dict):
        continue
      url = str(ref.get("url") or "").strip()
      platform = str(ref.get("platform") or "").strip().lower()
      if url and (platform == "notion" or "notion.so" in url):
        targets.append(normalize_target(url))

  targets.extend(normalize_target(url) for url in NOTION_URL_RE.findall(body))
  return unique_preserve_order(targets)


def extract_linear_refs(frontmatter: dict[str, Any], body: str, primary_linear: str | None) -> tuple[list[str], list[str]]:
  refs = unique_preserve_order(ENG_RE.findall(f"{frontmatter.get('linear', '')}\n{body}"))
  urls = unique_preserve_order(normalize_target(url) for url in LINEAR_URL_RE.findall(body))
  if primary_linear and primary_linear not in refs:
    refs.insert(0, primary_linear)
  return refs, urls


def build_task_record(path: pathlib.Path) -> dict[str, Any]:
  frontmatter, body = parse_task_file(path)
  slug = str(frontmatter.get("slug") or path.stem)
  primary_linear = parse_primary_linear(slug, frontmatter.get("linear"))
  linear_refs, linear_urls = extract_linear_refs(frontmatter, body, primary_linear)
  notion_targets = extract_notion_targets(frontmatter, body)

  return {
    "slug": slug,
    "status": str(frontmatter.get("status") or ""),
    "project": str(frontmatter.get("project") or ""),
    "repos": ensure_list(frontmatter.get("repos")),
    "pr_numbers": parse_pr_numbers(frontmatter.get("pr")),
    "primary_linear": primary_linear,
    "linear_refs": linear_refs,
    "linear_urls": linear_urls,
    "linear_query": f"identifier: {primary_linear}" if primary_linear else "",
    "notion_targets": notion_targets,
    "next_action": str(frontmatter.get("next_action") or ""),
  }


def render_markdown(ldap: str, tasks: list[dict[str, Any]]) -> None:
  print(f"# init scan seeds — {ldap}")
  print()
  print("Use exact targets first during `/worklog init --full`:")
  print("- Linear: query `linear_query` when present before any semantic search.")
  print("- Notion: fetch direct `notion_targets` before semantic search.")
  print()
  for task in tasks:
    print(f"- **{task['slug']}** [{task['status']}]")
    if task["primary_linear"]:
      print(f"  linear: {task['primary_linear']}  →  `{task['linear_query']}`")
    if task["notion_targets"]:
      print(f"  notion: {', '.join(task['notion_targets'])}")
    if task["pr_numbers"]:
      print(f"  prs: {', '.join(f'#{n}' for n in task['pr_numbers'])}")


def main() -> None:
  ldap, fmt = sys.argv[1:3]
  active_dir = pathlib.Path(f"people/{ldap}/active")
  tasks: list[dict[str, Any]] = []
  if active_dir.exists():
    tasks = [build_task_record(path) for path in sorted(active_dir.glob("*.md"))]

  if fmt == "json":
    print(json.dumps({"ldap": ldap, "tasks": tasks}, indent=2))
    return
  if fmt != "markdown":
    print(f"init-scan: unsupported format: {fmt}", file=sys.stderr)
    raise SystemExit(2)
  render_markdown(ldap, tasks)


if __name__ == "__main__":
  main()
