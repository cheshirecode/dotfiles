#!/usr/bin/env bash
# Snapshot any uncommitted worklog changes. Safe to call anytime — no-op if clean.
# Used by Claude PreCompact / SessionEnd hooks and anyone wanting a slugless save.
#
# Emits a `Worklog-Trigger:` trailer (pre-compact | session-end | manual) so
# `git log` consumers can filter autosave noise. See AGENTS.md § Checkpoint discipline.

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

if [[ -z "$(git status --porcelain)" ]]; then
  exit 0
fi

git pull --no-rebase --autostash -q 2>/dev/null || true
git add -A
git commit -q \
  -m "autosave: snapshot $(date +%Y-%m-%dT%H:%M:%S%z)" \
  -m "Worklog-Trigger: $TRIGGER" 2>/dev/null || exit 0

# Push debounce: PreCompact + SessionEnd hooks can fire within seconds of
# each other. Commit always; skip push when the previous commit was also an
# autosave within 10s — let the next flush carry both. Saves a network hit
# without losing any work (the local commit is already there).
LAST_SUBJECT="$(git log -1 --skip=1 --format=%s 2>/dev/null || true)"
LAST_TS="$(git log -1 --skip=1 --format=%ct 2>/dev/null || echo 0)"
NOW_TS="$(date +%s)"
if [[ "$LAST_SUBJECT" == autosave:* ]] && (( NOW_TS - LAST_TS < 10 )); then
  echo "autosave: debounced push (previous autosave $((NOW_TS - LAST_TS))s ago); next flush will carry it" >&2
  exit 0
fi

push_with_retry || exit 1
# Cross-task advisory now lives in bin/git-hooks/post-commit (broader coverage:
# fires on every commit, not only when autosave snapshots). TTL gate identical.
