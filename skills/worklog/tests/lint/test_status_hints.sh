#!/usr/bin/env bash
# A wrong status must not strand a fresh task behind the pre-commit hook with
# only a list to guess from. Observed 2026-09-01: a session creating a new
# task under active/ wrote `status: active` (the directory name) and was
# hard-blocked until it guessed 'draft'. The FSM stays six states; the error
# now carries a hint for the common wrong values. Assert the hint fires for
# 'active', and that a valid status still lints clean.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

mkdir -p "$TMP/wl/people/tester/active"
cd "$TMP/wl" && git init -q --initial-branch=main

task() {  # task <status>
  printf -- '---\nslug: thing\nstatus: %s\nkind: impl\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n## Context\nc\n\n## Next\n- [ ] x\n' "$1" \
    > people/tester/active/thing.md
}

run() { OUT=$(WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
              bash "$ROOT/bin/lint.sh" 2>&1); RC=$?; }

task active
run
printf '%s' "$OUT" | grep -q "status 'active' not in FSM" \
  && ck "wrong status is still an error" pass pass \
  || ck "wrong status is still an error" fail pass
printf '%s' "$OUT" | grep -q 'directory is a location, not a status' \
  && ck "'active' error carries the directory-name hint" pass pass \
  || ck "'active' error carries the directory-name hint" fail pass

task done
run
printf '%s' "$OUT" | grep -q "status 'done' not in FSM.*use 'archived'" \
  && ck "'done' error points at archived" pass pass \
  || ck "'done' error points at archived" fail pass

task in-progress
run
printf '%s' "$OUT" | grep -q 'not in FSM' \
  && ck "valid status lints clean" fail pass \
  || ck "valid status lints clean" pass pass

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
