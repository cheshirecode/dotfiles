#!/usr/bin/env bash
# Shared helpers for derived-query scripts (children.sh, pr.sh, stale.sh).
# Ensures .cache/index.jsonl exists and is not older than MAX_AGE_SECONDS.

set -euo pipefail

INDEX=".cache/index.jsonl"
MAX_AGE_SECONDS=${WORKLOG_INDEX_MAX_AGE:-300}

_need_rebuild() {
  [ ! -f "$INDEX" ] && return 0
  local mtime now
  # Try GNU stat first, BSD as fallback. -f succeeds on Linux but shows
  # filesystem info (non-numeric), which then chokes arithmetic under
  # set -u. See bin/_lib.sh::resolve_ldap for the same idiom.
  mtime=$(stat -c %Y "$INDEX" 2>/dev/null || stat -f %m "$INDEX" 2>/dev/null || echo 0)
  [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
  now=$(date +%s)
  [ $((now - mtime)) -gt "$MAX_AGE_SECONDS" ] && return 0
  python3 - "$INDEX" "$mtime" <<'PY'
import json
import pathlib
import sys

index = pathlib.Path(sys.argv[1])
index_mtime = float(sys.argv[2])

for state in ("active", "archive"):
  for path in pathlib.Path("people").glob(f"*/{state}/*.md"):
    try:
      if path.stat().st_mtime > index_mtime + 1e-3:
        sys.exit(0)
    except OSError:
      sys.exit(0)

try:
  for line in index.read_text().splitlines():
    if not line.strip():
      continue
    file_path = pathlib.Path(json.loads(line).get("file", ""))
    if not file_path.exists():
      sys.exit(0)
except Exception:
  sys.exit(0)

sys.exit(1)
PY
}

ensure_index() {
  if _need_rebuild; then
    "$SCRIPT_DIR/index.sh" >/dev/null
  fi
}
