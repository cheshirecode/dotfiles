#!/usr/bin/env bash
# `status: blocked` requires next_action to start with "Waiting on" (FSM
# contract). The linter enforced it as an ERROR, but only on a later run — so
# checkpoint.sh would happily put a task into a state the same toolchain then
# reported as broken. Observed 2026-08-31: a generated child stub flipped to
# blocked kept its "Awaiting claim — child of ..." default and became the
# corpus's only error, days after the transition that caused it.
#
# Refuse at the transition. Assert BOTH directions: the refusal fires, and a
# correct blocked transition still goes through.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

G() { git -c user.email=t@t.t -c user.name=t "$@"; }
G init -q --bare "$TMP/origin.git"
G init -q --initial-branch=main "$TMP/wl"; cd "$TMP/wl"
G remote add origin "$TMP/origin.git"
mkdir -p people/tester/active

task() {  # task <next_action>
  printf -- '---\nslug: thing\nowner: tester\nstatus: draft\nkind: impl\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "%s"\n---\n\n## Context\n\nc\n\n## Next\n\n- [ ] x\n' "$1" \
    > people/tester/active/thing.md
}
task "Awaiting claim — child of some-program"
G add -A && G commit -qm base >/dev/null 2>&1
G push -q -u origin main

run() { OUT=$(WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
              bash "$ROOT/bin/checkpoint.sh" "$@" 2>&1); RC=$?; }

# The generated default is exactly what bit us.
run thing --status=blocked
[ "$RC" = 2 ] && ck "blocked with a non-Waiting-on next_action is refused" pass pass \
              || ck "blocked with a non-Waiting-on next_action is refused" "exit $RC" pass
printf '%s' "$OUT" | grep -q 'Waiting on' \
  && ck "the refusal says what is required" pass pass \
  || ck "the refusal says what is required" fail pass
printf '%s' "$OUT" | grep -q 'Awaiting claim' \
  && ck "the refusal shows the current value" pass pass \
  || ck "the refusal shows the current value" fail pass

# ...and it must not have written anything.
grep -q 'status: draft' people/tester/active/thing.md \
  && ck "refused transition left the file alone" pass pass \
  || ck "refused transition left the file alone" fail pass

# --next supplied on the same call satisfies it.
run thing --status=blocked --next="Waiting on ENG-1514"
[ "$RC" = 0 ] && ck "blocked with --next=Waiting on ... is accepted" pass pass \
              || ck "blocked with --next=Waiting on ... is accepted" "exit $RC" pass
grep -q 'status: blocked' people/tester/active/thing.md \
  && ck "accepted transition wrote the status" pass pass \
  || ck "accepted transition wrote the status" fail pass

# An existing Waiting-on next_action satisfies it with no --next.
task "Waiting on the payments team"
G add -A && G commit -qm reset >/dev/null 2>&1
run thing --status=blocked
[ "$RC" = 0 ] && ck "existing Waiting-on next_action needs no --next" pass pass \
              || ck "existing Waiting-on next_action needs no --next" "exit $RC" pass

# Other statuses are untouched by the guard.
task "do the thing"
G add -A && G commit -qm reset2 >/dev/null 2>&1
run thing --status=in-progress
[ "$RC" = 0 ] && ck "in-progress is unaffected by the blocked guard" pass pass \
              || ck "in-progress is unaffected by the blocked guard" "exit $RC" pass

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
