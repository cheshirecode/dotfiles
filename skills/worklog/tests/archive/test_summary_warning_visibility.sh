#!/usr/bin/env bash
# archive.sh refuses a missing --summary up front; and where the refusal is
# deliberately bypassed, the warning must still reach a batch that redirects
# both streams.
#
# The failure originally pinned here: the warning was printed early, on stderr
# only. A session archived five tasks in a loop under `>/dev/null 2>&1`, saw
# nothing, and five tasks reached archive/ with no summary. A warning printed
# only to a suppressed stream does not exist.
#
# A warning was not enough — 60 of 244 archived tasks ended up with no summary
# — so archive.sh now refuses PRE-FLIGHT instead. The warning path survives
# for callers that take the documented escape, and everything this test
# already pinned about that path is still pinned, now exercised through the
# escape rather than through the default.
#
# Assertions:
#   1. the gate — no --summary and no escape refuses with rc 2 and writes
#      NOTHING: no commit, task still in active/, file byte-identical.
#   2. ordering — under the escape, the warning is said last, after
#      `archive: pushed`, so an interactive archive leaves it on screen.
#   3. survival — under the escape with both streams redirected, it still
#      lands on the controlling terminal. WORKLOG_TTY stands in for /dev/tty.
#   4. a supplied --summary stays quiet and lands in frontmatter.
#   5. an archive that is allowed to proceed still exits 0, because callers
#      run archive.sh under `set -e`.
set -euo pipefail

# The documented bypass. Every no-summary archive below is deliberate.
export WORKLOG_ARCHIVE_NO_SUMMARY=1

. "$(cd "$(dirname "$0")" && pwd)/_vault.sh"

make_vault

commit_task() {
  write_task "$1"
  git -C "$SCRATCH" add "people/tester/active/$1.md"
  git -C "$SCRATCH" commit -q -m "add $1" --no-verify
}

# --- 0. the gate: no --summary, no escape, nothing written ---
commit_task gate-task
before_head="$(git -C "$SCRATCH" rev-parse HEAD)"
before_sum="$(cksum < "$SCRATCH/people/tester/active/gate-task.md")"
set +e
gate_out="$(env -u WORKLOG_ARCHIVE_NO_SUMMARY "$WORKLOG_BIN/archive.sh" gate-task --reason=shipped 2>&1)"
gate_rc=$?
set -e
[[ $gate_rc -eq 2 ]] || { echo "FAIL: missing --summary exited $gate_rc, expected 2"; printf '%s\n' "$gate_out"; exit 1; }
grep -q 'refusing to archive' <<< "$gate_out" \
  || { echo "FAIL: refusal did not say why"; printf '%s\n' "$gate_out"; exit 1; }
[[ "$(git -C "$SCRATCH" rev-parse HEAD)" == "$before_head" ]] \
  || { echo "FAIL: the refusal still committed something"; exit 1; }
[[ -f "$SCRATCH/people/tester/active/gate-task.md" ]] \
  || { echo "FAIL: the refusal moved the task out of active/"; exit 1; }
[[ "$(cksum < "$SCRATCH/people/tester/active/gate-task.md")" == "$before_sum" ]] \
  || { echo "FAIL: the refusal modified the task file"; exit 1; }

# --- 1. ordering: warning comes after the push line (under the escape) ---
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

# --- 4. an archive allowed to proceed still exits 0 (callers use set -e) ---
commit_task exit-task
set +e
WORKLOG_TTY="$TTY_LOG" "$WORKLOG_BIN/archive.sh" exit-task --reason=shipped >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 0 ]] || { echo "FAIL: permitted archive without --summary exited $rc"; exit 1; }

rm -rf "$SCRATCH_ROOT"
echo "ok: missing --summary refuses and writes nothing; under the escape the warning is said last and survives a redirected batch"
