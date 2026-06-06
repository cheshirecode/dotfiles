#!/usr/bin/env bash
# pr.sh — find tasks referencing a PR number (frontmatter pr: or body #N).
#
# Usage:
#   bin/pr.sh <pr-number>
#
# Output: slug <TAB> state <TAB> status <TAB> source <TAB> file
#   source ∈ {frontmatter, body}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
# shellcheck source=_query.sh
. "$SCRIPT_DIR/_query.sh"

PR="${1:-}"
case "$PR" in
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") echo "usage: pr.sh <pr-number>" >&2; exit 2 ;;
esac
PR="${PR#\#}"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "pr.sh: not a number: $PR" >&2; exit 2; }

ensure_index

jq -r --argjson pr "$PR" '
  . as $r
  | if ($r.pr // [] | index($pr)) then
      [$r.slug, $r.state, $r.status, "frontmatter", $r.file]
    elif ($r.body_refs.prs // [] | index($pr)) then
      [$r.slug, $r.state, $r.status, "body", $r.file]
    else empty end
  | @tsv
' "$INDEX"
