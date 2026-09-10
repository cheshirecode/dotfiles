#!/usr/bin/env bash
# Print a one-line-per-active-task roster from .cache/compact-kernels.json or
# directly from active task Markdown when the derived view is unavailable.
#
# Why: the preamble used to Read .cache/compact-kernels.md (~95KB / ~23k
# tokens) unconditionally. This emits the same data shape at ~1-3k tokens:
# top-N tasks by last_updated, with next_action truncated to ~120 chars.
# The full .md remains on disk for human review / grep; readers that need
# detail open the per-task file directly (one Read instead of all).
#
# Output (one task per line, tab-separated):
#   <slug>	<status>	<next_action[:120]>
# Plus a leading meta line:
#   # roster: shown <N>/<total> tasks, kernels-age=<seconds>
#
# Flags:
#   --limit=N     show top N by last_updated (default: 15)
#   --all         no cap (used when caller wants the full list)
#   --raw         read active task Markdown without touching the cache

set -euo pipefail

LIMIT=15
RAW=0
for arg in "$@"; do
  case "$arg" in
    --limit=*) LIMIT="${arg#--limit=}" ;;
    --all)     LIMIT=99999 ;;
    --raw)     RAW=1 ;;
    *) echo "kernels-roster: unknown arg '$arg'" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

if (( RAW == 1 )); then
  LDAP="$(resolve_ldap)"
  ACTIVE_DIR="people/$LDAP/active"
  python3 - "$ACTIVE_DIR" "$LIMIT" "$SCRIPT_DIR" <<'PY'
import pathlib
import sys
sys.path.insert(0, sys.argv[3])
from _task_context import parse_task_file

active_dir = pathlib.Path(sys.argv[1])
limit = int(sys.argv[2])
records = []

for path in sorted(active_dir.glob("*.md")):
    text = path.read_text(errors="replace")
    fields, _ = parse_task_file(text)
    if not fields:
        continue
    slug = str(fields.get("slug") or path.stem)
    records.append(
        (
            str(fields.get("last_updated") or ""),
            slug,
            str(fields.get("status") or "-"),
            " ".join(str(fields.get("next_action") or "-").split()),
        )
    )

records.sort(key=lambda record: (record[0], record[1]), reverse=True)
shown = min(limit, len(records))
print(f"# roster: raw fallback shown {shown}/{len(records)} tasks")
for _, slug, status, next_action in records[:limit]:
    print(f"{slug}\t{status}\t{next_action[:120]}")
PY
  exit 0
fi

JSON="$REPO_ROOT/.cache/compact-kernels.json"

if [[ ! -f "$JSON" ]]; then
  echo "kernels-roster: .cache/compact-kernels.json missing — run bin/compact-kernels.sh" >&2
  exit 1
fi

age=$(( $(date +%s) - $(stat -c %Y "$JSON" 2>/dev/null || stat -f %m "$JSON") ))
if (( age > 3600 )); then
  printf '# roster: kernels stale (age=%ss > 3600s) — skipped; run %s/compact-kernels.sh\n' "$age" "$SCRIPT_DIR"
  exit 0
fi
freshness="$(python3 - "$JSON" "$SCRIPT_DIR" <<'PY_STATE'
import json, sys
sys.path.insert(0, sys.argv[2])
from _task_context import cache_freshness
try:
    with open(sys.argv[1]) as f:
        print(cache_freshness(json.load(f)))
except (OSError, ValueError):
    print("invalid")
PY_STATE
)"
if [[ "$freshness" != "fresh" ]]; then
  printf '# roster: kernels %s — skipped; run %s/compact-kernels.sh\n' "$freshness" "$SCRIPT_DIR"
  [[ "$freshness" == "stale" ]] && exit 0
  exit 1
fi
total=$(jq 'length' "$JSON")
shown=$(( LIMIT < total ? LIMIT : total ))

printf '# roster: shown %s/%s tasks, kernels-age=%ss\n' "$shown" "$total" "$age"
jq -r --argjson n "$LIMIT" '
  sort_by(.last_updated // "0000-00-00") | reverse | .[0:$n]
  | .[] | "\(.slug)\t\(.status // "-")\t\((.next_action // "-") | .[0:120])"
' "$JSON"
