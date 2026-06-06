#!/usr/bin/env bash
# children.sh — list tasks whose parent_slug = <slug>, or which mention <slug>
# in `related[]` or body_refs.slugs.
#
# Usage:
#   bin/children.sh <slug>              # parent_slug matches only
#   bin/children.sh <slug> --include-refs  # also include related[] + body mentions
#
# Output: tab-separated — slug <TAB> kind <TAB> status <TAB> relation <TAB> file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
# shellcheck source=_query.sh
. "$SCRIPT_DIR/_query.sh"

SLUG=""
INCLUDE_REFS=0
for arg in "$@"; do
  case "$arg" in
    --include-refs) INCLUDE_REFS=1 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "children.sh: unknown arg: $arg" >&2; exit 2 ;;
    *) SLUG="$arg" ;;
  esac
done
[ -z "$SLUG" ] && { echo "usage: children.sh <slug> [--include-refs]" >&2; exit 2; }

ensure_index

jq -r --arg slug "$SLUG" --argjson refs "$INCLUDE_REFS" '
  . as $r
  | if $r.parent_slug == $slug then
      [$r.slug, $r.kind, $r.status, "parent_slug", $r.file]
    elif $refs == 1 and ($r.related // [] | map(.slug) | index($slug)) then
      [$r.slug, $r.kind, $r.status, "related", $r.file]
    elif $refs == 1 and ($r.body_refs.slugs // [] | index($slug)) then
      [$r.slug, $r.kind, $r.status, "body-mention", $r.file]
    elif $r.supersedes == $slug then
      [$r.slug, $r.kind, $r.status, "supersedes", $r.file]
    elif $r.reopens == $slug then
      [$r.slug, $r.kind, $r.status, "reopens", $r.file]
    else empty end
  | @tsv
' "$INDEX"
