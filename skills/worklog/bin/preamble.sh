#!/usr/bin/env bash
# One-shot preamble for /worklog modes. Replaces the prose preamble that used
# to consume 6-7 tool turns per mode (LDAP resolve / projects-dir resolve /
# pull / namespace check / kernel roster, all sequenced).
#
# Modes:
#   --minimal   LDAP + projects-dir + namespace + kernel roster. No pull.
#               Use for status / context / project read-only.
#   --full      Above + rate-limited git pull (5-min stamp at
#               .cache/preamble-pull-stamp). Use for init / sync / review.
#   (default)   Same as --full.
#
# Output is line-shaped KEY=VAL for the caller (Claude) to parse, followed
# by a `### roster` block. Errors go to stderr; the script exits non-zero
# only on fatal misconfiguration.
#
# Idempotency: the pull is rate-limited by a 5-min stamp file. LDAP is
# cached 24h by bin/_lib.sh::resolve_ldap. Namespace creation is a one-shot
# `mkdir -p` + .gitkeep — costs nothing if already present.

set -euo pipefail

mode="${1:---full}"
case "$mode" in
  --minimal|--full) ;;
  *) echo "usage: $0 [--minimal|--full]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

LDAP="$(resolve_ldap)"
PROJECTS_DIR="$(dirname "$REPO_ROOT")"

printf 'LDAP=%s\n' "$LDAP"
printf 'PROJECTS_DIR=%s\n' "$PROJECTS_DIR"

# Namespace check — create silently if missing (matches preamble step 4).
ns="people/$LDAP"
if [[ ! -d "$ns" ]]; then
  mkdir -p "$ns/active" "$ns/archive"
  : > "$ns/archive/.gitkeep"
  printf 'NAMESPACE=created\n'
else
  printf 'NAMESPACE=exists\n'
fi

active_total="$(find people -path '*/active/*.md' -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
active_namespace="$(find "people/$LDAP/active" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
dirty_count="$(git status --porcelain -- people docs bin 2>/dev/null | wc -l | tr -d '[:space:]')"
ahead_count="0"
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead_count="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  ahead_count="$(printf '%s' "$ahead_count" | tr -d '[:space:]')"
fi
printf 'ACTIVE_TOTAL=%s\n' "${active_total:-0}"
printf 'ACTIVE_NAMESPACE=%s\n' "${active_namespace:-0}"
printf 'GIT_DIRTY=%s\n' "${dirty_count:-0}"
printf 'GIT_AHEAD=%s\n' "${ahead_count:-0}"

# Pull rate limit (5 min). Always for --full; never for --minimal.
PULL_STAMP=".cache/preamble-pull-stamp"
if [[ "$mode" == "--full" ]]; then
  pull_age=99999
  [[ -f "$PULL_STAMP" ]] && pull_age=$(( $(date +%s) - $(stat -c %Y "$PULL_STAMP" 2>/dev/null || stat -f %m "$PULL_STAMP") ))
  if (( pull_age > 300 )); then
    git config pull.rebase false >/dev/null
    git config pull.ff true >/dev/null
    # Pre-pull dirty check — autosave silently if needed.
    if ! detect_dirty_worklog >/dev/null 2>&1; then
      bash "$SCRIPT_DIR/autosave.sh" >/dev/null 2>&1 || true
    fi
    if git pull --no-rebase --autostash --quiet >/dev/null 2>&1; then
      mkdir -p .cache
      touch "$PULL_STAMP"
      printf 'PULL=fresh\n'
    else
      printf 'PULL=failed (continuing with local)\n'
    fi
  else
    printf 'PULL=skip (age=%ss<300s)\n' "$pull_age"
  fi
else
  printf 'PULL=skip (minimal)\n'
fi

# Roster (kernels JSON one-liner per active task). The health line is
# intentionally separate so fresh agents can tell "no roster" from "no work".
printf '\n### roster\n'
if [[ -f .cache/compact-kernels.json ]]; then
  kernel_mtime="$(stat -c %Y .cache/compact-kernels.json 2>/dev/null || stat -f %m .cache/compact-kernels.json 2>/dev/null || echo 0)"
  kernel_age=$(( $(date +%s) - kernel_mtime ))
  kernel_count="$(python3 - <<'PY' 2>/dev/null || echo unknown
import json
print(len(json.load(open(".cache/compact-kernels.json"))))
PY
)"
  if [[ "$kernel_age" -gt 3600 ]]; then
    printf '# roster-health: stale age=%ss active_namespace=%s active_total=%s\n' "$kernel_age" "${active_namespace:-0}" "${active_total:-0}"
  elif [[ "$kernel_count" != "${active_namespace:-0}" ]]; then
    printf '# roster-health: mismatch kernels=%s active_namespace=%s active_total=%s\n' "$kernel_count" "${active_namespace:-0}" "${active_total:-0}"
  else
    printf '# roster-health: fresh kernels=%s active_namespace=%s active_total=%s\n' "$kernel_count" "${active_namespace:-0}" "${active_total:-0}"
  fi
  bash "$SCRIPT_DIR/kernels-roster.sh"
else
  printf '# roster-health: missing active_namespace=%s active_total=%s\n' "${active_namespace:-0}" "${active_total:-0}"
  printf '# roster: kernels missing — run %s/compact-kernels.sh\n' "$SCRIPT_DIR"
fi
