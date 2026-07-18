#!/usr/bin/env python3
"""Reconcile authoritative Worklog-PR trailers with current GitHub PR state."""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any

import yaml


EXPECTED_GITHUB_STATES = {
  "draft": ["OPEN"],
  "in-progress": ["OPEN"],
  "blocked": ["OPEN"],
  "in-review": ["OPEN"],
  "shipping": ["MERGED"],
  "archived": ["MERGED"],
}


def fail(message: str, code: int = 2) -> None:
  print(f"reconcile-pr: {message}", file=sys.stderr)
  raise SystemExit(code)


def read_task(repo: pathlib.Path, slug: str) -> tuple[pathlib.Path, dict[str, Any]]:
  matches = sorted(repo.glob(f"people/*/active/{slug}.md"))
  matches += sorted(repo.glob(f"people/*/archive/{slug}.md"))
  if not matches:
    fail(f"no task file for '{slug}'")
  if len(matches) > 1:
    fail(f"multiple task files resolve for '{slug}'")
  text = matches[0].read_text()
  match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
  if not match:
    fail(f"task '{slug}' has no YAML frontmatter")
  frontmatter = yaml.safe_load(match.group(1)) or {}
  if not isinstance(frontmatter, dict):
    fail(f"task '{slug}' frontmatter is not a mapping")
  return matches[0], frontmatter


def authoritative_prs(repo: pathlib.Path, slug: str) -> list[int]:
  result = subprocess.run(
    [
      "git", "log", "--all",
      "--format=%x1e%(trailers:key=Worklog-Slug,valueonly=true,separator=%x09)%x1f%(trailers:key=Worklog-PR,valueonly=true,separator=%x09)",
    ],
    cwd=repo,
    capture_output=True,
    text=True,
    check=True,
  )
  numbers: set[int] = set()
  for record in result.stdout.split("\x1e"):
    if "\x1f" not in record:
      continue
    slug_text, pr_text = record.strip("\n\r ").split("\x1f", 1)
    slugs = {value.strip() for value in re.split(r"[\t,]", slug_text) if value.strip()}
    if slug not in slugs:
      continue
    numbers.update(int(value) for value in re.findall(r"\d+", pr_text))
  return sorted(numbers)


def remote_repo(path: pathlib.Path) -> str | None:
  if not path.exists():
    return None
  result = subprocess.run(
    ["git", "remote", "get-url", "origin"],
    cwd=path,
    capture_output=True,
    text=True,
  )
  if result.returncode != 0:
    return None
  match = re.search(r"github\.com(?::|/)([^/\s]+/[^/\s]+?)(?:\.git)?$", result.stdout.strip())
  return match.group(1) if match else None


def resolve_repo(frontmatter: dict[str, Any], pr: int) -> str:
  pr_repos = frontmatter.get("pr_repos") or {}
  if isinstance(pr_repos, dict):
    explicit = pr_repos.get(pr) or pr_repos.get(str(pr))
    if explicit:
      return str(explicit)

  repos = frontmatter.get("repos") or []
  raw = str(repos[0]) if isinstance(repos, list) and repos else ""
  if not raw:
    fail(f"task has no repository for PR #{pr}")

  known = [value.strip() for value in os.environ.get("WORKLOG_KNOWN_REPOS", "").split(",") if value.strip()]
  exact = [value for value in known if value == raw]
  suffix = [value for value in known if value.rsplit("/", 1)[-1] == raw.rsplit("/", 1)[-1]]
  if exact:
    return exact[0]
  if len(suffix) == 1:
    return suffix[0]

  projects_dir = os.environ.get("PROJECTS_DIR")
  if projects_dir:
    root = pathlib.Path(projects_dir)
    for candidate in (root / raw, root / raw.rsplit("/", 1)[-1]):
      resolved = remote_repo(candidate)
      if resolved:
        return resolved

  if "/" in raw:
    return raw
  fail(f"cannot resolve GitHub repository for '{raw}'; set pr_repos or WORKLOG_KNOWN_REPOS")
  raise AssertionError("unreachable")


def fetch_pr(repo: str, pr: int) -> dict[str, Any]:
  result = subprocess.run(
    ["gh", "pr", "view", str(pr), "-R", repo, "--json", "number,state,url,isDraft,mergedAt"],
    capture_output=True,
    text=True,
  )
  if result.returncode != 0:
    detail = result.stderr.strip() or "gh pr view returned non-zero"
    fail(f"failed to fetch {repo}#{pr}: {detail}", 1)
  try:
    value = json.loads(result.stdout)
  except json.JSONDecodeError as exc:
    fail(f"failed to parse {repo}#{pr}: {exc}", 1)
  state = "MERGED" if value.get("mergedAt") else str(value.get("state") or "UNKNOWN").upper()
  return {
    "pr": pr,
    "repo": repo,
    "state": state,
    "is_draft": bool(value.get("isDraft")),
    "url": value.get("url"),
  }


def main(argv: list[str]) -> None:
  if len(argv) != 2 or argv[1] in {"-h", "--help"}:
    print("usage: reconcile-pr.sh <slug>", file=sys.stderr)
    raise SystemExit(0 if len(argv) == 2 else 2)

  repo = pathlib.Path(argv[0]).resolve()
  slug = argv[1]
  _task_path, frontmatter = read_task(repo, slug)
  prs = authoritative_prs(repo, slug)
  if not prs:
    fail(f"no authoritative Worklog-PR trailer for '{slug}'")

  worklog_status = str(frontmatter.get("status") or "unknown")
  expected_states = EXPECTED_GITHUB_STATES.get(worklog_status, ["OPEN"])
  observed = [fetch_pr(resolve_repo(frontmatter, pr), pr) for pr in prs]
  mismatches = [
    {
      "pr": item["pr"],
      "repo": item["repo"],
      "expected": expected_states,
      "observed": item["state"],
    }
    for item in observed
    if item["state"] not in expected_states
  ]
  output = {
    "slug": slug,
    "expected": {"worklog_status": worklog_status, "github_states": expected_states},
    "observed": observed,
    "observed_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "source": [item["url"] for item in observed if item["url"]],
    "mismatches": mismatches,
  }
  print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
  main(sys.argv[1:])
