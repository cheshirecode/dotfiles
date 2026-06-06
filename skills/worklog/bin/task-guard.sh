#!/usr/bin/env bash
# task-guard.sh — classify dirty task files against a claimed slug.
#
# Usage:
#   bin/task-guard.sh --slug=<slug> [--slug=<slug> ...] [--include=PATH ...]
#   bin/task-guard.sh --slug=<slug> --format=json
#
# Exit codes:
#   0  no foreign dirty task files
#   2  one or more dirty task files are outside the claimed slug(s)
#
# Read-only. Intended for agent/skill preflight before broad write paths.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SLUGS=()
INCLUDES=()
FORMAT="text"

usage() {
  sed -n '2,13p' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug=*) SLUGS+=("${1#--slug=}") ;;
    --slug)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SLUGS+=("$2")
      shift
      ;;
    --include=*) INCLUDES+=("${1#--include=}") ;;
    --include)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      INCLUDES+=("$2")
      shift
      ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --format)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      FORMAT="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "task-guard: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ "${#SLUGS[@]}" -eq 0 ]]; then
  echo "task-guard: --slug is required" >&2
  usage
  exit 2
fi

if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
  echo "task-guard: --format must be text or json" >&2
  exit 2
fi

python3 - "$FORMAT" "${SLUGS[*]}" "${INCLUDES[*]-}" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

fmt, slug_arg, include_arg = sys.argv[1:4]
claimed = [s for s in slug_arg.split() if s]
includes = [p for p in include_arg.split() if p]

root = pathlib.Path.cwd()

def norm(path: str) -> str:
  p = pathlib.Path(path)
  if p.is_absolute():
    try:
      return str(p.resolve().relative_to(root))
    except ValueError:
      return str(p)
  return str(p)

include_set = {norm(p) for p in includes}
task_re = re.compile(r"^people/([^/]+)/(active|archive)/([^/]+)\.md$")

raw = subprocess.check_output(
  ["git", "status", "--porcelain=v1", "-z", "--", "people"],
  text=False,
)
entries = [e.decode("utf-8", "replace") for e in raw.split(b"\0") if e]

dirty_tasks = []
i = 0
while i < len(entries):
  entry = entries[i]
  status = entry[:2]
  path = entry[3:] if len(entry) > 3 else ""
  i += 1

  # In porcelain -z, rename/copy entries are followed by the source path.
  # The first path is the destination/current path, which is what matters for
  # guarding the dirty worktree.
  if status and status[0] in {"R", "C"} and i < len(entries):
    i += 1

  path = norm(path)
  m = task_re.match(path)
  if not m:
    continue
  dirty_tasks.append({
    "path": path,
    "ldap": m.group(1),
    "state": m.group(2),
    "slug": m.group(3),
    "status": status,
    "allowed": m.group(3) in claimed or path in include_set,
  })

foreign = [t for t in dirty_tasks if not t["allowed"]]
result = {
  "claimed_slugs": claimed,
  "allowed_paths": sorted(include_set),
  "dirty_task_paths": [t["path"] for t in dirty_tasks],
  "foreign_task_paths": [t["path"] for t in foreign],
  "dirty_tasks": dirty_tasks,
}

if fmt == "json":
  print(json.dumps(result, indent=2, sort_keys=True))
else:
  if foreign:
    print("task-guard: foreign dirty task files detected", file=sys.stderr)
    print(f"  claimed slug(s): {', '.join(claimed)}", file=sys.stderr)
    for task in foreign:
      print(f"  - {task['path']} ({task['status'].strip() or 'dirty'})", file=sys.stderr)
    print("  Treat these as owned by another session; do not autosave/stage them.", file=sys.stderr)
  else:
    if dirty_tasks:
      print("task-guard: dirty task files are within claimed slug(s)")
    else:
      print("task-guard: no dirty task files")

sys.exit(2 if foreign else 0)
PY
