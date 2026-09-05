#!/usr/bin/env bash
# A Worklog-Status: trailer can be the stale side of a divergence — accurate
# frontmatter over a trailer nobody re-asserted. The lint warning used to advise
# aligning frontmatter DOWN to the trailer, and that was the ONLY move available:
# `--status=X` when frontmatter already read X hit "no changes" and wrote no
# trailer, so the divergence was unfixable through the path meant to fix it.
# Reported live 2026-08-31 on a task whose 'in-review' was correct.
#
# Assert the re-assert path exists, that it is gated on real divergence (no
# empty-commit noise), and that it never fires without an explicit --status.
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
printf -- '---\nslug: thing\nowner: tester\nstatus: in-review\nkind: impl\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n## Context\n\nc\n\n## Next\n\n- [ ] x\n' \
  > people/tester/active/thing.md
G add -A && G commit -qm base >/dev/null 2>&1
G push -q -u origin main

run() { OUT=$(WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
              bash "$ROOT/bin/checkpoint.sh" "$@" 2>&1); RC=$?; }

# checkpoint normalizes the file on its first run (last_updated, quoting), so
# the no-op path — the one this bug lives on — is only reachable at steady
# state. Get there first, or the fixture tests the ordinary write path and
# passes for the wrong reason.
run thing >/dev/null 2>&1
run thing >/dev/null 2>&1
# ...then plant the STALE trailer: says draft, frontmatter says in-review.
G commit -q --allow-empty -m "thing: old checkpoint" -m "Worklog-Status: draft" -m "Worklog-Slug: thing"
G push -q origin HEAD
BEFORE=$(G rev-list --count HEAD)

# The move the new advice recommends must actually work.
run thing --status=in-review
[ "$RC" = 0 ] && ck "re-assert exits 0" pass pass || ck "re-assert exits 0" "exit $RC" pass
printf '%s' "$OUT" | grep -q 're-assert' \
  && ck "re-assert path is taken on divergence" pass pass \
  || ck "re-assert path is taken on divergence" fail pass
[ "$(G rev-list --count HEAD)" = "$((BEFORE+1))" ] \
  && ck "exactly one commit was written" pass pass \
  || ck "exactly one commit was written" "$(G rev-list --count HEAD)" "$((BEFORE+1))"
G log -1 --format='%(trailers:key=Worklog-Status,valueonly=true)' | grep -q 'in-review' \
  && ck "the commit carries the corrected trailer" pass pass \
  || ck "the commit carries the corrected trailer" fail pass
grep -q 'status: in-review' people/tester/active/thing.md \
  && ck "frontmatter was NOT degraded to the stale value" pass pass \
  || ck "frontmatter was NOT degraded to the stale value" fail pass

# Now aligned: a second call must be a quiet no-op, not another empty commit.
N=$(G rev-list --count HEAD)
run thing --status=in-review
[ "$(G rev-list --count HEAD)" = "$N" ] \
  && ck "no empty commit when already aligned" pass pass \
  || ck "no empty commit when already aligned" "$(G rev-list --count HEAD)" "$N"
printf '%s' "$OUT" | grep -q 'already asserted' \
  && ck "the aligned no-op says why" pass pass \
  || ck "the aligned no-op says why" fail pass

# Without --status, a no-op stays a plain no-op — no commit, no re-assert.
run thing
[ "$(G rev-list --count HEAD)" = "$N" ] \
  && ck "plain checkpoint never re-asserts" pass pass \
  || ck "plain checkpoint never re-asserts" "$(G rev-list --count HEAD)" "$N"

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
