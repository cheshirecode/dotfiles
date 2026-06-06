#!/usr/bin/env python3
"""Helpers for bin/project.sh.

Subcommands invoked from the shell driver:

  plan-new     Read SLUG, GOAL, OBJECTIVE, STALE_AFTER, LDAP, TODAY, TASKS_JSON
               from env. Emit a JSON plan describing the project file + each
               child task stub (path + body). Does not touch disk.

  materialize-new
               Read the same plan JSON from stdin and write every file to disk.
               Refuses if any target file already exists.

  next         Read PROJECT_SLUG from env. Walk the project's tasks: list and
               print the first declaration-order claim-eligible task slug
               (every dep has status: archived; phase-1 ignores claims).
               Exit 0 with slug on stdout; exit 1 with reason on stderr if
               nothing eligible.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys

import yaml

SLUG_RE = re.compile(r"^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$")
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def die(msg: str, code: int = 1) -> None:
  print(msg, file=sys.stderr)
  sys.exit(code)


def find_task_path(slug: str) -> pathlib.Path | None:
  for state in ("active", "archive"):
    for p in sorted(pathlib.Path("people").glob(f"*/{state}/{slug}.md")):
      return p
  return None


def parse_frontmatter(path: pathlib.Path) -> dict:
  text = path.read_text()
  m = FRONTMATTER_RE.match(text)
  if not m:
    return {}
  try:
    fm = yaml.safe_load(m.group(1))
    return fm if isinstance(fm, dict) else {}
  except yaml.YAMLError:
    return {}


def yaml_quote(s: str) -> str:
  return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_project_body(slug: str, goal: str, objective: str, stale_after: str,
                        ldap: str, today: str, tasks: list[dict],
                        repos: list[str]) -> str:
  repos_str = "[" + ", ".join(repos) + "]" if repos else "[]"
  lines = [
    "---",
    f"slug: {slug}",
    "status: draft",
    "kind: project",
    f"repos: {repos_str}",
    "project: none",
    "owner: " + ldap,
    f"created: {today}",
    f"last_updated: {today}",
    f"next_action: {yaml_quote('Kick off — claim first eligible child task with bin/project.sh next ' + slug)}",
    f"goal: {yaml_quote(goal)}",
    f"objective: {yaml_quote(objective)}",
    "mutex:",
    f"  stale_after: {stale_after}",
    "tasks:",
  ]
  for t in tasks:
    lines.append(f"  - slug: {t['slug']}")
    if t.get("depends_on"):
      deps = ", ".join(t["depends_on"])
      lines.append(f"    depends_on: [{deps}]")
    if t.get("kind"):
      lines.append(f"    kind: {t['kind']}")
  # Auto-sync tasks: → related: so cross-task lint recognizes the declared
  # parent/child relationship without a follow-up --fix-related pass.
  lines.append("related:")
  for i, t in enumerate(tasks):
    note = f"Child task (tasks[{i}] in this project's tasks block)."
    lines.append(f"  - slug: {t['slug']}")
    lines.append(f"    note: {yaml_quote(note)}")
  lines += [
    "---",
    "",
    "## Goal",
    "",
    goal,
    "",
    "## Objective",
    "",
    objective,
    "",
    "## Tasks",
    "",
  ]
  for t in tasks:
    deps = t.get("depends_on") or []
    deps_str = f" (depends on: {', '.join(deps)})" if deps else ""
    lines.append(f"- [ ] [[{t['slug']}]]{deps_str}")
  lines += [
    "",
    "## Next",
    "",
    f"- [ ] Run `bin/project.sh next {slug}` to pick the first claim-eligible child.",
    "",
  ]
  return "\n".join(lines) + "\n"


def render_child_body(child_slug: str, parent_slug: str, ldap: str, today: str,
                      title: str | None, depends_on: list[str],
                      kind: str = "impl", repos: list[str] | None = None) -> str:
  # depends_on lives in the parent's tasks: block per spec — do NOT emit it on
  # the child stub's frontmatter. parent_slug is sufficient back-reference.
  _ = depends_on
  repos = repos or []
  repos_str = "[" + ", ".join(repos) + "]" if repos else "[]"
  lines = [
    "---",
    f"slug: {child_slug}",
    "status: draft",
    f"kind: {kind}",
    f"repos: {repos_str}",
    f"project: {parent_slug}",
    f"parent_slug: {parent_slug}",
    f"last_updated: {today}",
    f"next_action: {yaml_quote('Awaiting claim — child of ' + parent_slug)}",
    "---",
    "",
    "## Context",
    "",
    title or f"Child task of [[{parent_slug}]].",
    "",
    "## Next",
    "",
    "- [ ] Claim via `bin/project.sh claim " + child_slug + "` (phase 2)",
    "",
  ]
  return "\n".join(lines) + "\n"


def cmd_plan_new() -> None:
  slug = os.environ["SLUG"]
  goal = os.environ["GOAL"]
  objective = os.environ["OBJECTIVE"]
  stale_after = os.environ.get("STALE_AFTER", "30m")
  ldap = os.environ["LDAP"]
  today = os.environ["TODAY"]
  raw = os.environ["TASKS_JSON"]
  repos_raw = os.environ.get("REPOS", "")
  repos = [r.strip() for r in repos_raw.split(",") if r.strip()]

  if not SLUG_RE.match(slug):
    die(f"plan-new: invalid project slug '{slug}'")

  try:
    tasks = json.loads(raw)
  except json.JSONDecodeError as e:
    die(f"plan-new: tasks JSON parse error: {e}")
  if not isinstance(tasks, list) or not tasks:
    die("plan-new: tasks JSON must be a non-empty array")

  # Validate each task.
  seen: set[str] = set()
  for t in tasks:
    if not isinstance(t, dict) or "slug" not in t:
      die(f"plan-new: each task must be an object with 'slug'; got {t!r}")
    cs = t["slug"]
    if not SLUG_RE.match(cs):
      die(f"plan-new: invalid child slug '{cs}'")
    if cs in seen:
      die(f"plan-new: duplicate child slug '{cs}'")
    seen.add(cs)
    if cs == slug:
      die(f"plan-new: child slug equals project slug '{slug}'")
    deps = t.get("depends_on") or []
    if not isinstance(deps, list):
      die(f"plan-new: depends_on for '{cs}' must be a list")
    for d in deps:
      if d not in seen and d not in {x["slug"] for x in tasks}:
        die(f"plan-new: '{cs}' depends_on '{d}' which is not in tasks")

  # Refuse if any target file already exists.
  active_dir = pathlib.Path("people") / ldap / "active"
  project_path = active_dir / f"{slug}.md"
  if find_task_path(slug):
    die(f"plan-new: project slug '{slug}' already exists on disk")
  for t in tasks:
    if find_task_path(t["slug"]):
      die(f"plan-new: child slug '{t['slug']}' already exists on disk")

  project_body = render_project_body(slug, goal, objective, stale_after,
                                     ldap, today, tasks, repos)
  children = []
  for t in tasks:
    cs = t["slug"]
    # Per-task repos override; else children inherit the project's repos.
    child_repos = t.get("repos") if isinstance(t.get("repos"), list) else repos
    body = render_child_body(cs, slug, ldap, today, t.get("title"),
                             t.get("depends_on") or [], t.get("kind", "impl"),
                             child_repos)
    children.append({
      "slug": cs,
      "path": str(active_dir / f"{cs}.md"),
      "depends_on": t.get("depends_on") or [],
      "body": body,
    })

  plan = {
    "slug": slug,
    "ldap": ldap,
    "goal": goal,
    "objective": objective,
    "stale_after": stale_after,
    "project_path": str(project_path),
    "project_body": project_body,
    "children": children,
  }
  print(json.dumps(plan))


def cmd_materialize_new() -> None:
  plan = json.load(sys.stdin)
  proj_path = pathlib.Path(plan["project_path"])
  if proj_path.exists():
    die(f"materialize-new: refusing to overwrite {proj_path}")
  proj_path.parent.mkdir(parents=True, exist_ok=True)
  # Ensure archive dir + .gitkeep so the LDAP layout is complete.
  archive_dir = proj_path.parent.parent / "archive"
  archive_dir.mkdir(parents=True, exist_ok=True)
  gk = archive_dir / ".gitkeep"
  if not gk.exists():
    gk.write_text("")
  proj_path.write_text(plan["project_body"])
  for c in plan["children"]:
    cp = pathlib.Path(c["path"])
    if cp.exists():
      die(f"materialize-new: refusing to overwrite {cp}")
    cp.write_text(c["body"])


def _eligible_list(slug: str) -> list[str]:
  proj_path = find_task_path(slug)
  if proj_path is None:
    die(f"eligible-list: no task file for '{slug}'", code=1)
  fm = parse_frontmatter(proj_path)
  tasks = fm.get("tasks") or []
  out: list[str] = []
  def status_of(child_slug: str) -> str:
    p = find_task_path(child_slug)
    if p is None:
      return "missing"
    cfm = parse_frontmatter(p)
    return cfm.get("status") or "draft"
  for t in tasks:
    if not isinstance(t, dict) or "slug" not in t:
      continue
    cs = t["slug"]
    cs_status = status_of(cs)
    if cs_status in ("archived", "missing"):
      continue
    deps = t.get("depends_on") or []
    if all(status_of(d) == "archived" for d in deps):
      out.append(cs)
  return out


def cmd_next() -> None:
  slug = os.environ["PROJECT_SLUG"]
  proj_path = find_task_path(slug)
  if proj_path is None:
    die(f"project next: no task file for '{slug}'", code=1)
  fm = parse_frontmatter(proj_path)
  if fm.get("kind") != "project":
    die(f"project next: '{slug}' is kind:{fm.get('kind')} not kind:project", code=1)
  tasks = fm.get("tasks") or []
  if not isinstance(tasks, list) or not tasks:
    die(f"project next: '{slug}' has no tasks: block", code=1)

  eligible = _eligible_list(slug)
  if eligible:
    print(eligible[0])
    return

  # Build a reasons report for the human.
  reasons: list[str] = []
  for t in tasks:
    if not isinstance(t, dict) or "slug" not in t:
      continue
    cs = t["slug"]
    p = find_task_path(cs)
    if p is None:
      reasons.append(f"{cs}: missing file")
      continue
    cfm = parse_frontmatter(p)
    cstatus = cfm.get("status") or "draft"
    if cstatus == "archived":
      continue
    deps = t.get("depends_on") or []
    blocked = [d for d in deps if (parse_frontmatter(find_task_path(d)).get("status") if find_task_path(d) else "missing") != "archived"]
    if blocked:
      reasons.append(f"{cs}: blocked on {','.join(blocked)}")
  if not reasons:
    die(f"project next: all tasks for '{slug}' are archived (nothing left)", code=1)
  die("project next: no claim-eligible task; " + "; ".join(reasons), code=1)


def _all_projects() -> list[pathlib.Path]:
  out: list[pathlib.Path] = []
  for state in ("active", "archive"):
    for p in sorted(pathlib.Path("people").glob(f"*/{state}/*.md")):
      fm = parse_frontmatter(p)
      if fm.get("kind") == "project":
        out.append(p)
  return out


def _verify_one(project_path: pathlib.Path) -> tuple[list[str], list[str]]:
  """Return (errors, warnings) for a single project file."""
  errors: list[str] = []
  warnings: list[str] = []
  fm = parse_frontmatter(project_path)
  proj_slug = fm.get("slug") or project_path.stem
  tasks = fm.get("tasks") or []
  if not isinstance(tasks, list):
    errors.append(f"{proj_slug}: tasks: must be a list")
    return errors, warnings

  declared = {t["slug"] for t in tasks if isinstance(t, dict) and "slug" in t}

  # Dep cycle check (Kahn-ish).
  graph: dict[str, list[str]] = {}
  for t in tasks:
    if not isinstance(t, dict) or "slug" not in t:
      continue
    graph[t["slug"]] = list(t.get("depends_on") or [])

  # Every dep must resolve to a declared slug.
  for s, deps in graph.items():
    for d in deps:
      if d not in declared:
        errors.append(f"{proj_slug}: task '{s}' depends_on '{d}' which is not declared in tasks:")

  # Cycle detection via DFS.
  WHITE, GRAY, BLACK = 0, 1, 2
  color = {n: WHITE for n in graph}
  cycles: list[str] = []
  def dfs(n: str, stack: list[str]) -> None:
    color[n] = GRAY
    stack.append(n)
    for d in graph.get(n, []):
      if d not in color:
        continue
      if color[d] == GRAY:
        cycles.append("->".join(stack[stack.index(d):] + [d]))
      elif color[d] == WHITE:
        dfs(d, stack)
    stack.pop()
    color[n] = BLACK
  for n in graph:
    if color[n] == WHITE:
      dfs(n, [])
  for c in cycles:
    errors.append(f"{proj_slug}: dependency cycle: {c}")

  # parent_slug ↔ tasks consistency.
  for cs in declared:
    cp = find_task_path(cs)
    if cp is None:
      errors.append(f"{proj_slug}: declared child '{cs}' has no task file")
      continue
    cfm = parse_frontmatter(cp)
    parent = cfm.get("parent_slug")
    if parent != proj_slug:
      warnings.append(f"{proj_slug}: child '{cs}' has parent_slug={parent!r}, expected {proj_slug!r}")

  # Orphan claims with stale heartbeats (active tasks under this project).
  import datetime as _dt
  mutex = fm.get("mutex") or {}
  stale_after = mutex.get("stale_after") or "30m"
  m = re.match(r"^\s*(\d+)\s*([smhd])\s*$", stale_after)
  if not m:
    warnings.append(f"{proj_slug}: mutex.stale_after '{stale_after}' is unparseable; using 30m")
    stale_sec = 1800
  else:
    stale_sec = int(m.group(1)) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
  for cs in declared:
    cp = find_task_path(cs)
    if cp is None:
      continue
    cfm = parse_frontmatter(cp)
    claim = cfm.get("claim") or {}
    if not claim:
      continue
    hb = claim.get("heartbeat_at") or claim.get("lock_at")
    if not hb:
      warnings.append(f"{proj_slug}: child '{cs}' has claim but no heartbeat_at/lock_at")
      continue
    try:
      hb_dt = _dt.datetime.fromisoformat(str(hb).replace("Z", "+00:00"))
      age = (_dt.datetime.now(_dt.timezone.utc) - hb_dt).total_seconds()
    except Exception:
      warnings.append(f"{proj_slug}: child '{cs}' has unparseable heartbeat_at: {hb}")
      continue
    if age > stale_sec:
      warnings.append(f"{proj_slug}: child '{cs}' has stale claim (age {int(age)}s > {stale_sec}s) by {claim.get('session_id')}")

  return errors, warnings


def cmd_verify(argv: list[str]) -> int:
  if not argv:
    print("usage: project.sh verify <slug> | verify --all", file=sys.stderr)
    return 2
  if argv[0] == "--all":
    targets = _all_projects()
  else:
    p = find_task_path(argv[0])
    if p is None:
      print(f"verify: no task file for '{argv[0]}'", file=sys.stderr)
      return 2
    fm = parse_frontmatter(p)
    if fm.get("kind") != "project":
      print(f"verify: '{argv[0]}' is kind:{fm.get('kind')} not kind:project", file=sys.stderr)
      return 2
    targets = [p]

  total_err = 0
  total_warn = 0
  for t in targets:
    errs, warns = _verify_one(t)
    for e in errs:
      print(f"ERROR  {e}")
    for w in warns:
      print(f"warn   {w}")
    total_err += len(errs)
    total_warn += len(warns)
  print(f"verify: {len(targets)} project(s); {total_err} error(s), {total_warn} warning(s)")
  if total_err:
    return 2
  if total_warn:
    return 1
  return 0


def cmd_list(_argv: list[str]) -> int:
  projects = _all_projects()
  if not projects:
    print("project list: no kind:project tasks found")
    return 0
  for p in projects:
    fm = parse_frontmatter(p)
    slug = fm.get("slug") or p.stem
    status = fm.get("status") or "?"
    tasks = fm.get("tasks") or []
    rollup: dict[str, int] = {}
    held = 0
    for t in tasks:
      if not isinstance(t, dict) or "slug" not in t:
        continue
      cp = find_task_path(t["slug"])
      if cp is None:
        rollup["missing"] = rollup.get("missing", 0) + 1
        continue
      cfm = parse_frontmatter(cp)
      cstatus = cfm.get("status") or "draft"
      rollup[cstatus] = rollup.get(cstatus, 0) + 1
      if cfm.get("claim"):
        held += 1
    parts = [f"{k}={v}" for k, v in sorted(rollup.items())]
    held_str = f" held={held}" if held else ""
    print(f"{slug}  [{status}]  ({len(tasks)} tasks: {', '.join(parts)}){held_str}")
  return 0


def main() -> None:
  if len(sys.argv) < 2:
    die("usage: _project.py {plan-new|materialize-new|next}", code=2)
  cmd = sys.argv[1]
  if cmd == "plan-new":
    cmd_plan_new()
  elif cmd == "materialize-new":
    cmd_materialize_new()
  elif cmd == "next":
    cmd_next()
  elif cmd == "eligible-list":
    for s in _eligible_list(os.environ["PROJECT_SLUG"]):
      print(s)
  elif cmd == "verify":
    sys.exit(cmd_verify(sys.argv[2:]))
  elif cmd == "list":
    sys.exit(cmd_list(sys.argv[2:]))
  elif cmd == "print-dry-plan":
    plan = json.load(sys.stdin)
    print(f"-- DRY-RUN: would write project file: {plan['project_path']}")
    print(plan["project_body"])
    for c in plan["children"]:
      print(f"-- DRY-RUN: would write child stub: {c['path']}")
      print(c["body"])
  elif cmd == "print-create-meta":
    # Read plan from stdin, print SUBJECT / BODY / TRAILERS / PATHS on stdout
    # separated by null-delimited records the shell can consume.
    plan = json.load(sys.stdin)
    out = {
      "subject": f"{plan['slug']}: create project",
      "body": (
        f"goal: {plan['goal']}\n"
        f"objective: {plan['objective']}\n"
        f"children:\n"
        + "\n".join(
          "  - " + c["slug"]
          + (f" (deps: {','.join(c['depends_on'])})" if c.get("depends_on") else "")
          for c in plan["children"]
        )
      ),
      "trailers": "\n".join(
        ["Worklog-Slug: " + plan["slug"], "Worklog-Kind: project", "Worklog-Status: draft"]
        + ["Worklog-Slug: " + c["slug"] for c in plan["children"]]
      ),
      "paths": [plan["project_path"]] + [c["path"] for c in plan["children"]],
    }
    print(json.dumps(out))
  else:
    die(f"_project.py: unknown command '{cmd}'", code=2)


if __name__ == "__main__":
  main()
