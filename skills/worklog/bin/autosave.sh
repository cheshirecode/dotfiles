#!/usr/bin/env bash
# Snapshot uncommitted worklog changes. Safe to call anytime — no-op if clean.
# Used by Claude PreCompact / SessionEnd hooks and anyone wanting a slugless save.
#
# Default scope: people/$LDAP/ only (WORKLOG_AUTOSAVE_WIDE=1 for full tree).
# Consecutive hook fires amend the previous unpushed autosave instead of a new commit.
#
# Emits Worklog-Trigger + Worklog-Paths trailers. See AGENTS.md § Checkpoint discipline.

set -euo pipefail

TRIGGER="manual"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger=*) TRIGGER="${1#--trigger=}" ;;
    --trigger)   TRIGGER="$2"; shift ;;
    -h|--help)   echo "usage: autosave.sh [--trigger=pre-compact|session-end|manual]"; exit 0 ;;
    *) echo "autosave: unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

LDAP="$(resolve_ldap)"

if [[ -z "$(git status --porcelain)" ]]; then
  exit 0
fi

git pull --no-rebase --autostash -q 2>/dev/null || true

if ! autosave_stage_paths; then
  if [[ -z "${WORKLOG_AUTOSAVE_WIDE:-}" || "${WORKLOG_AUTOSAVE_WIDE:-0}" != "1" ]]; then
    foreign="$(git status --porcelain -- people/ docs/ bin/ projects/ 2>/dev/null \
      | grep -v "^.. people/$LDAP/" || true)"
    if [[ -n "$foreign" ]]; then
      echo "autosave: dirty outside people/$LDAP/ — set WORKLOG_AUTOSAVE_WIDE=1 to include" >&2
    fi
  fi
  exit 0
fi

PATHS_TRAILER="$(autosave_paths_trailer)"
TS="$(date +%Y-%m-%dT%H:%M:%S%z)"
COMMIT_ARGS=(-q -m "autosave: snapshot $TS" -m "Worklog-Trigger: $TRIGGER")
[[ -n "$PATHS_TRAILER" ]] && COMMIT_ARGS+=(-m "Worklog-Paths: $PATHS_TRAILER")

if autosave_can_amend_head; then
  git commit --amend "${COMMIT_ARGS[@]}" 2>/dev/null || exit 0
else
  git commit "${COMMIT_ARGS[@]}" 2>/dev/null || exit 0
fi

mkdir -p .cache
date +%s > .cache/autosave-last-run

# Push debounce: PreCompact + SessionEnd can fire within seconds. Commit always;
# skip push when the previous commit was also autosave within 10s — flush later.
LAST_SUBJECT="$(git log -1 --skip=1 --format=%s 2>/dev/null || true)"
LAST_TS="$(git log -1 --skip=1 --format=%ct 2>/dev/null || echo 0)"
NOW_TS="$(date +%s)"
if [[ "$LAST_SUBJECT" == autosave:* ]] && (( NOW_TS - LAST_TS < 10 )); then
  touch .cache/autosave-push-pending
  echo "autosave: debounced push (previous autosave $((NOW_TS - LAST_TS))s ago); run autosave-flush or next push carries it" >&2
  exit 0
fi

if push_with_retry; then
  rm -f .cache/autosave-push-pending
fi
