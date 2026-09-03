#!/usr/bin/env bash
# archive.sh must not rewrite a task it cannot move.
#
# The failure this pins: the body-edit sets `status: archived` and writes the
# file, and only *then* runs `git mv`. On an untracked task that mv dies with
# `fatal: not under version control` — but the rewrite already landed, so the
# task sits in active/ marked archived with next_action cleared. The command
# "failed", so nobody looks; the next lint blames the file instead of the tool.
#
# The load-bearing assertion is therefore about CONTENT, not exit status: after
# a refused archive the file must be byte-identical to what it was before.
set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/_vault.sh"

make_vault
write_task untracked-task

SRC="$SCRATCH/people/tester/active/untracked-task.md"
# Deliberately NOT git-added: this is the untracked case.
before="$(cat "$SRC")"

set +e
out="$("$WORKLOG_BIN/archive.sh" untracked-task --reason=shipped --summary="x" 2>&1)"
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  echo "FAIL: archive of an untracked task reported success"
  printf '%s\n' "$out"
  exit 1
fi

# The real defect: partial write survives the failed move.
after="$(cat "$SRC")"
if [[ "$before" != "$after" ]]; then
  echo "FAIL: task body was rewritten even though the move could not succeed"
  echo "--- diff (before -> after) ---"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
  exit 1
fi
if grep -q '^status: archived' "$SRC"; then
  echo "FAIL: untracked task left in active/ marked status: archived"
  exit 1
fi
if grep -q '^Archived ' "$SRC" || grep -q 'Archived 20' "$SRC"; then
  echo "FAIL: archive marker written into a task that never moved"
  exit 1
fi

# It must refuse *before* doing work, and say why in terms the caller can act on.
if ! grep -q 'not tracked by git' <<< "$out"; then
  echo "FAIL: refusal did not name untracked-ness as the reason"
  printf '%s\n' "$out"
  exit 1
fi

# And nothing may have been left staged or committed by the aborted run.
if git -C "$SCRATCH" log --oneline | grep -q 'untracked-task'; then
  echo "FAIL: a commit was created for a task that was never archived"
  exit 1
fi

# Control: the same task, tracked, archives cleanly. Guards against a fix that
# simply refuses everything.
git -C "$SCRATCH" add "people/tester/active/untracked-task.md"
git -C "$SCRATCH" commit -q -m "track the task" --no-verify
"$WORKLOG_BIN/archive.sh" untracked-task --reason=shipped --summary="now tracked" >/dev/null 2>&1
[[ -f "$SCRATCH/people/tester/archive/untracked-task.md" ]] \
  || { echo "FAIL: tracked task did not reach archive/"; exit 1; }
[[ ! -f "$SRC" ]] || { echo "FAIL: tracked task still in active/"; exit 1; }

rm -rf "$SCRATCH_ROOT"
echo "ok: archive refuses an untracked task before rewriting it, and still archives tracked ones"
