#!/usr/bin/env bash
# Render a standup-shaped summary from `git log` + Worklog-* trailers.
# Read-only. Parses commits since <since>, groups by current-status-in-file.
#
# Usage:
#   bin/status.sh                              # today (since=midnight), self, markdown
#   bin/status.sh --since=yesterday
#   bin/status.sh --since=1.week.ago --author=alice
#   bin/status.sh --slug=eng-1515-stack        # single-task history
#   bin/status.sh --format=json                # machine-readable
#   bin/status.sh --include-meta               # keep protocol:/bin:/docs:

set -euo pipefail

SINCE="midnight"
AUTHOR=""
SLUG=""
PROJECT=""
FORMAT="markdown"
INCLUDE_META=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since=*)   SINCE="${1#--since=}" ;;
    --author=*)  AUTHOR="${1#--author=}" ;;
    --slug=*)    SLUG="${1#--slug=}" ;;
    --project=*) PROJECT="${1#--project=}" ;;
    --format=*)  FORMAT="${1#--format=}" ;;
    --include-meta) INCLUDE_META=1 ;;
    --since)     SINCE="$2"; shift ;;
    --author)    AUTHOR="$2"; shift ;;
    --slug)      SLUG="$2"; shift ;;
    --project)   PROJECT="$2"; shift ;;
    --format)    FORMAT="$2"; shift ;;
    -h|--help)
      cat <<EOF
usage: status.sh [--since=<git-date>] [--author=cheshirecode] [--slug=<slug>]
                 [--project=<slug>] [--format=markdown|grouped|json] [--include-meta]
  --since       default: midnight (today). Examples: yesterday, 1.week.ago, 2026-04-15.
  --author      default: self (resolved from $WORKLOG_LDAP / git config).
  --slug        single-task view; follows renames via Worklog-Previous-Slug.
  --project     filter + group by Linear/worklog project slug.
  --format      markdown (default, standup-shaped), grouped (legacy per-project), or json.
  --include-meta  don't filter protocol:/bin:/docs: subjects.
EOF
      exit 0
      ;;
    *) echo "status: unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
[[ -z "$AUTHOR" ]] && AUTHOR="$(resolve_ldap)"

# Emit JSON per commit: {sha, subject, slug, next, status, pr, kind, linear, prev_slug}
# Python does the parsing — awk gets brittle with multiline bodies.
LOG_ARGS=(--since="$SINCE" --author="$AUTHOR@" --format='%x00%H%x1f%s%x1f%b%x1e')
if [[ $INCLUDE_META -eq 0 ]]; then
  LOG_ARGS+=(--invert-grep --grep='^\(autosave\|protocol\|bin\|docs\)\b')
fi
if [[ -n "$SLUG" ]]; then
  # Full history for one slug (follows renames via Worklog-Previous-Slug trailer).
  LOG_ARGS=(--all --format='%x00%H%x1f%s%x1f%b%x1e' \
    --grep="^${SLUG}:" --grep="Worklog-Previous-Slug: ${SLUG}\$" --regexp-ignore-case)
fi


git log "${LOG_ARGS[@]}" | python3 "$(dirname "${BASH_SOURCE[0]}")/_status.py" \
  "$FORMAT" "$AUTHOR" "$SINCE" "$SLUG" "$PROJECT"
