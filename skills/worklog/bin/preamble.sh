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
cd "$REPO_ROOT"
# shellcheck source=/dev/null
. "$REPO_ROOT/bin/_lib.sh"

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

# Roster (kernels JSON one-liner per active task).
printf '\n### roster\n'
if [[ -f .cache/compact-kernels.json ]]; then
  bash "$SCRIPT_DIR/kernels-roster.sh"
else
  printf '# roster: kernels missing — run bin/compact-kernels.sh\n'
fi
