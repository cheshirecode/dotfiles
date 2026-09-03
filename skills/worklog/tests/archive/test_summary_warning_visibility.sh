#!/usr/bin/env bash
# The no---summary warning must reach a batch that redirects both streams.
#
# The failure this pins: the warning was printed early, on stderr only. A
# session archived five tasks in a loop under `>/dev/null 2>&1`, saw nothing,
# and five tasks reached archive/ with no summary. A warning printed only to a
# suppressed stream does not exist.
#
# Two assertions:
#   1. ordering — the warning is the last thing said, after `archive: pushed`,
#      so a single interactive archive leaves it on screen rather than 80 lines
#      up. (Red before the fix: it printed before any of the work.)
#   2. survival — with stdout and stderr both redirected, it still lands on the
#      controlling terminal. WORKLOG_TTY stands in for /dev/tty so the fixture
#      can read it. (Red before the fix: nothing is written anywhere.)
set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/_vault.sh"

make_vault

commit_task() {
  write_task "$1"
  git -C "$SCRATCH" add "people/tester/active/$1.md"
  git -C "$SCRATCH" commit -q -m "add $1" --no-verify
}

# --- 1. ordering: warning comes after the push line ---
commit_task order-task
out="$("$WORKLOG_BIN/archive.sh" order-task --reason=shipped 2>&1)"
pushed_line="$(grep -n '^archive: pushed order-task$' <<< "$out" | head -1 | cut -d: -f1)"
warn_line="$(grep -n 'no --summary' <<< "$out" | head -1 | cut -d: -f1)"
if [[ -z "$pushed_line" ]]; then
  echo "FAIL: no 'archive: pushed' line at all"; printf '%s\n' "$out"; exit 1
fi
if [[ -z "$warn_line" ]]; then
  echo "FAIL: no --summary warning emitted"; printf '%s\n' "$out"; exit 1
fi
if (( warn_line < pushed_line )); then
  echo "FAIL: no---summary warning printed at line $warn_line, before the push line at $pushed_line"
  echo "      a warning said before the work is the one a batch scrolls past"
  printf '%s\n' "$out"
  exit 1
fi

# --- 2. survival: both streams redirected, warning still surfaces ---
TTY_LOG="$SCRATCH_ROOT/tty.log"
: > "$TTY_LOG"
for slug in batch-a batch-b batch-c; do
  commit_task "$slug"
  WORKLOG_TTY="$TTY_LOG" "$WORKLOG_BIN/archive.sh" "$slug" --reason=shipped >/dev/null 2>&1
done
for slug in batch-a batch-b batch-c; do
  [[ -f "$SCRATCH/people/tester/archive/$slug.md" ]] \
    || { echo "FAIL: $slug did not archive"; exit 1; }
  if ! grep -q "$slug" "$TTY_LOG"; then
    echo "FAIL: batch archive of $slug under '>/dev/null 2>&1' surfaced no warning anywhere"
    echo "--- captured terminal channel ---"
    cat "$TTY_LOG"
    exit 1
  fi
done

# --- 3. a supplied --summary stays quiet, and lands in the archived file ---
commit_task quiet-task
: > "$TTY_LOG"
out="$(WORKLOG_TTY="$TTY_LOG" "$WORKLOG_BIN/archive.sh" quiet-task \
        --reason=shipped --summary="Recapped properly." 2>&1)"
if grep -q 'no --summary' <<< "$out"; then
  echo "FAIL: warned about a missing summary that was supplied"; exit 1
fi
if [[ -s "$TTY_LOG" ]]; then
  echo "FAIL: wrote to the terminal channel for an archive that had a summary"
  cat "$TTY_LOG"; exit 1
fi
grep -q 'summary: "Recapped properly."' "$SCRATCH/people/tester/archive/quiet-task.md" \
  || { echo "FAIL: --summary not written into frontmatter"; exit 1; }

# --- 4. a successful archive still exits 0 (callers run it under set -e) ---
commit_task exit-task
set +e
WORKLOG_TTY="$TTY_LOG" "$WORKLOG_BIN/archive.sh" exit-task --reason=shipped >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "FAIL: successful archive without --summary exited $rc"; exit 1; }

rm -rf "$SCRATCH_ROOT"
echo "ok: no---summary warning is said last and survives a fully redirected batch"
