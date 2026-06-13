#!/usr/bin/env bash
# Build .cache/index.jsonl — a per-task JSONL record of every file under
# people/*/{active,archive}/. Regenerated on demand; never committed.
#
# Usage:
#   bin/index.sh              # write to .cache/index.jsonl
#   bin/index.sh --stdout     # print to stdout instead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

STDOUT=0
case "${1:-}" in
  --stdout) STDOUT=1 ;;
  -h|--help)
    cat <<EOF
usage: index.sh [--stdout]
  default: writes .cache/index.jsonl (one JSON record per task)
  --stdout: print to stdout, do not write the cache file
EOF
    exit 0
    ;;
  "") ;;
  *) echo "index.sh: unknown arg: $1" >&2; exit 2 ;;
esac

if [[ "$STDOUT" == "1" ]]; then
  exec python3 "$SCRIPT_DIR/_index.py"
fi

mkdir -p .cache
TMP="$(mktemp ".cache/index.jsonl.tmp.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
python3 "$SCRIPT_DIR/_index.py" > "$TMP"
mv -f "$TMP" .cache/index.jsonl
trap - EXIT
count=$(wc -l < .cache/index.jsonl | tr -d ' ')
echo ".cache/index.jsonl  $count tasks"
