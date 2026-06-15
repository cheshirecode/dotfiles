#!/usr/bin/env bash
# audit.sh — composite health report across the worklog corpus.
#
# Composes existing helpers into one summary so periodic review doesn't
# require running 4 commands and squinting at output. Each section is
# narrow and read-only; this script never mutates anything.
#
# Sections:
#   1. Stale (active, last_updated >= 14d ago)        — bin/stale.sh
#   2. Blocked too long (>=7d in blocked status)      — local jq
#   3. In-review too long (>=14d in in-review)        — local jq
#   4. Cross-task lint drift (declared-relation rot)  — "$SCRIPT_DIR/lint.sh" --cross-task
#   5. Boundary profile drift (foreign-domain terms)  — boundary-lint.sh
#   6. Command surface drift (README/AGENTS/skill)    — codex-surface-check.sh
#
# Usage:
#   bin/audit.sh                      # full report
#   bin/audit.sh --ldap=cheshirecode        # scope to one person
#   bin/audit.sh --section=<name>     # one of: stale, blocked, in-review, drift, boundary, surface
#
# Exit code is always 0 — this is a report, not a gate. Use lint.sh for CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LDAP=""
SECTION=""
for arg in "$@"; do
  case "$arg" in
    --ldap=*)    LDAP="${arg#--ldap=}" ;;
    --section=*) SECTION="${arg#--section=}" ;;
    -h|--help)   sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "audit: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
. "$SCRIPT_DIR/_query.sh"

ensure_index
TODAY=$(date +%Y-%m-%d)

run_section() {
  [[ -z "$SECTION" || "$SECTION" == "$1" ]]
}

age_filter() {
  local min_days="$1"
  local status="$2"
  jq -r \
    --arg today "$TODAY" \
    --argjson days "$min_days" \
    --arg status "$status" \
    --arg ldap "$LDAP" '
    def to_epoch_days($d):
      ($d | split("-") | map(tonumber)) as $p
      | ($p[0] * 365 + $p[1] * 30 + $p[2]);
    . as $r
    | select($r.state == "active" and $r.status == $status)
    | select($ldap == "" or $r.ldap == $ldap)
    | select($r.last_updated != "" and ($r.last_updated | test("^\\d{4}-\\d{2}-\\d{2}$")))
    | (to_epoch_days($today) - to_epoch_days($r.last_updated)) as $age
    | select($age >= $days)
    | [($age | tostring), $r.slug, $r.ldap, $r.file]
    | @tsv
  ' "$INDEX" | sort -nr
}

if run_section stale; then
  echo "=== Stale active tasks (last_updated ≥14d) ==="
  if [[ -n "$LDAP" ]]; then
    "$SCRIPT_DIR/stale.sh" --days=14 --ldap="$LDAP" || true
  else
    "$SCRIPT_DIR/stale.sh" --days=14 || true
  fi
  echo ""
fi

if run_section blocked; then
  echo "=== Blocked ≥7d (FSM: should be unblocking or escalating) ==="
  out="$(age_filter 7 blocked)"
  if [[ -z "$out" ]]; then
    echo "  (none)"
  else
    printf '  age_days\tslug\tldap\tfile\n'
    echo "$out" | sed 's/^/  /'
  fi
  echo ""
fi

if run_section in-review; then
  echo "=== In-review ≥14d (likely stale review — PR landed/abandoned?) ==="
  out="$(age_filter 14 in-review)"
  if [[ -z "$out" ]]; then
    echo "  (none)"
  else
    printf '  age_days\tslug\tldap\tfile\n'
    echo "$out" | sed 's/^/  /'
  fi
  echo ""
fi

if run_section drift; then
  echo "=== Cross-task drift (lint --cross-task warnings) ==="
  lint_json="$("$SCRIPT_DIR/lint.sh" --cross-task --format=json 2>/dev/null || true)"
  printf '%s' "$lint_json" | python3 -c '
import json, sys
try:
  data = json.load(sys.stdin)
except Exception:
  sys.exit(1)
issues = data.get("issues", [])
if not issues:
  print("  (clean)")
  sys.exit(0)
total_errors = data.get("total_errors", 0)
total_warnings = data.get("total_warnings", 0)
print(f"  {total_errors} error(s), {total_warnings} warning(s)")
for item in issues:
  path = item.get("file", "(unknown)")
  for err in item.get("errors", []):
    print(f"  ERROR   {path}: {err}")
  for warn in item.get("warnings", []):
    print(f"  warn    {path}: {warn}")
' || echo "  (lint unavailable)"
  echo ""
fi

if run_section boundary; then
  echo "=== Boundary profile drift (foreign-domain terms) ==="
  if [[ -f "$REPO_ROOT/.worklog-boundary.json" ]]; then
    "$SCRIPT_DIR/boundary-lint.sh" 2>&1 | sed 's/^/  /' || true
  else
    echo "  (no .worklog-boundary.json profile)"
  fi
  echo ""
fi

if run_section surface; then
  echo "=== Command surface drift (README / AGENTS / skill) ==="
  CODEX_SKILL_PATH="${CODEX_SKILL_PATH:-$SCRIPT_DIR/../SKILL.md}" \
    "$SCRIPT_DIR/codex-surface-check.sh" 2>&1 | sed 's/^/  /' || true
  echo ""
fi
