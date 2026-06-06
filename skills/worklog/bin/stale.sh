#!/usr/bin/env bash
# stale.sh — list active tasks whose last_updated is older than N days.
#
# Usage:
#   bin/stale.sh [--days=14] [--ldap=cheshirecode] [--status=<status>]
#
# Output: last_updated <TAB> age_days <TAB> slug <TAB> status <TAB> ldap <TAB> file
# Sorted oldest-first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
# shellcheck source=_query.sh
. "$SCRIPT_DIR/_query.sh"

DAYS=14
LDAP=""
STATUS=""
for arg in "$@"; do
  case "$arg" in
    --days=*) DAYS="${arg#--days=}" ;;
    --ldap=*) LDAP="${arg#--ldap=}" ;;
    --status=*) STATUS="${arg#--status=}" ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "stale.sh: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "stale.sh: bad --days: $DAYS" >&2; exit 2; }

ensure_index

TODAY=$(date +%Y-%m-%d)

jq -r \
  --arg today "$TODAY" \
  --argjson days "$DAYS" \
  --arg ldap "$LDAP" \
  --arg status "$STATUS" '
  def to_epoch_days($d):
    ($d | split("-") | map(tonumber)) as $p
    | ($p[0] * 365 + $p[1] * 30 + $p[2]);

  . as $r
  | select($r.state == "active")
  | select($r.last_updated != "" and ($r.last_updated | test("^\\d{4}-\\d{2}-\\d{2}$")))
  | select($ldap == "" or $r.ldap == $ldap)
  | select($status == "" or $r.status == $status)
  | (to_epoch_days($today) - to_epoch_days($r.last_updated)) as $age
  | select($age >= $days)
  | [$r.last_updated, ($age | tostring), $r.slug, $r.status, $r.ldap, $r.file]
  | @tsv
' "$INDEX" | sort
