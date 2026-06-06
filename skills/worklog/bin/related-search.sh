#!/usr/bin/env bash
# Pre-write context probe for new task creation.
#
# Two modes:
#   bin/related-search.sh <keyword>...     keyword search across active +
#                                          archive task bodies
#   bin/related-search.sh --projects       enumerate `project:` slugs in use
#
# Use BEFORE locking decisions in a new task body or before inventing a new
# project: value. A 5-second grep here prevents wrong-by-disagreement
# decisions later (see worklog-prior-art-check, AGENTS.md § sync mode).
set -euo pipefail

here="$(SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT" && pwd)/people"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,11p' "$0"
  exit 0
fi

if [ "${1:-}" = "--projects" ]; then
  awk '/^project:/{print $2}' "$here"/*/active/*.md "$here"/*/archive/*.md \
    2>/dev/null | sort -u
  exit 0
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <keyword>... | --projects" >&2
  exit 2
fi

for kw in "$@"; do
  echo "=== $kw ==="
  grep -lr -- "$kw" "$here"/*/active/ "$here"/*/archive/ 2>/dev/null | head -10
done
