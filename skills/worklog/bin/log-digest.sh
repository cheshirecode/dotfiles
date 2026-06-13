#!/usr/bin/env bash
# log-digest.sh — burst-folded view of `git log`. Read-only projection;
# never rewrites history. The actual squash tool is `bin/log-compact.sh`.
#
# A "burst" = ≥--min-burst consecutive same-slug `<slug>: checkpoint`
# commits, each pair within --burst-window seconds. Bursts collapse into
# one digest entry. Status/create/archive commits split bursts (they're
# meaningful events worth keeping verbatim).
#
# Usage:
#   bin/log-digest.sh                                          # last 7 days, default fold
#   bin/log-digest.sh --since=1.day.ago --slug=foo
#   bin/log-digest.sh --since=30.days.ago --format=json | jq .
#   bin/log-digest.sh --since=7.days.ago --obsidian-links      # vault-friendly output
#
# Flags:
#   --since=<git-date>    default: 7.days.ago. Use git-date syntax:
#                         '7.days.ago', '24.hours.ago', '2026-04-01', 'yesterday'.
#                         Bare 'Nd' / 'Nh' shortcuts do NOT work — git silently
#                         returns the wrong range.
#   --until=<git-date>    upper bound; default: now.
#   --slug=<slug>         scope to one slug (subject prefix `<slug>:`).
#   --min-burst=N         min run length to fold (default 3).
#   --burst-window=SEC    max seconds between consecutive burst members (default 14400 = 4h).
#   --format=md|json      default md.
#   --obsidian-links      emit body slug refs as [[slug]].

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

SINCE="7.days.ago"
UNTIL=""
SLUG=""
PASS=()

for arg in "$@"; do
  case "$arg" in
    --since=*) SINCE="${arg#--since=}" ;;
    --until=*) UNTIL="${arg#--until=}" ;;
    --slug=*) SLUG="${arg#--slug=}" ;;
    --min-burst=*|--burst-window=*|--format=*|--obsidian-links) PASS+=("$arg") ;;
    -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "log-digest: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

LOG_ARGS=(log --format='%H%x1f%ct%x1f%s%x1f%b%x1e' --since="$SINCE")
[[ -n "$UNTIL" ]] && LOG_ARGS+=(--until="$UNTIL")
[[ -n "$SLUG" ]] && LOG_ARGS+=(--grep="^${SLUG}:")

git "${LOG_ARGS[@]}" | python3 "$SCRIPT_DIR/_log_digest.py" \
  ${PASS[@]+"${PASS[@]}"}
