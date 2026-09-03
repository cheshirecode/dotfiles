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

# Collect the task directories that actually exist. A bare
# "$here"/*/active/*.md glob is passed through literally when it matches
# nothing, and the resulting "no such file" is fatal under `set -e` plus
# pipefail -- so a namespace with no archive/ yet (every new one) killed the
# probe. Building the list first makes "nothing to search" a stated condition
# rather than an accident of glob expansion.
mapfile -t SCOPE < <(find "$here" -type d \( -name active -o -name archive \) 2>/dev/null | sort)
if [ "${#SCOPE[@]}" -eq 0 ]; then
  echo "$(basename "$0"): no active/ or archive/ directories under $here" >&2
  exit 1
fi

if [ "${1:-}" = "--projects" ]; then
  mapfile -t FILES < <(find "${SCOPE[@]}" -name '*.md' -type f 2>/dev/null | sort)
  # awk with an empty argument list would read stdin and hang.
  [ "${#FILES[@]}" -eq 0 ] && exit 0
  awk '/^project:/{print $2}' "${FILES[@]}" | sort -u
  exit 0
fi

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <keyword>... | --projects" >&2
  exit 2
fi

for kw in "$@"; do
  echo "=== $kw ==="
  # grep exits 1 for "no matches", which is a verdict here, not an error.
  # Unguarded under `set -e` it aborted the whole probe on the first
  # unmatched keyword, so later keywords -- including ones with real prior
  # art -- were never searched and the run just stopped. Printing the verdict
  # keeps "searched, found nothing" distinct from "never got here".
  hits="$(grep -lr -- "$kw" "${SCOPE[@]}" 2>/dev/null | head -10 || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
  else
    echo "  (no matches)"
  fi
done
