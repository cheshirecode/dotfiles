#!/usr/bin/env bash
# Read-only seed pack for `/worklog init --full`.
# Emits exact Linear issue identifiers, Notion page targets, and PR numbers
# from active task files so the tool layer can do deterministic external scans.
# Cold-start safe: if people/<ldap>/active does not exist yet, emits zero tasks.
#
# Usage:
#   bin/init-scan.sh
#   bin/init-scan.sh --ldap <ldap>
#   bin/init-scan.sh --format=json

set -euo pipefail

LDAP=""
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ldap=*)   LDAP="${1#--ldap=}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --ldap)     LDAP="$2"; shift ;;
    --format)   FORMAT="$2"; shift ;;
    -h|--help)
      cat <<EOF
usage: init-scan.sh [--ldap=<ldap>] [--format=markdown|json]
  read-only seed pack for exact Linear / Notion / PR scans during init --full
EOF
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
[[ -z "$LDAP" ]] && LDAP="$(resolve_ldap)"

python3 "$(dirname "${BASH_SOURCE[0]}")/_init_scan.py" "$LDAP" "$FORMAT"
