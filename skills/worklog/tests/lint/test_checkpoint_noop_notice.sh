#!/usr/bin/env bash
# "checkpoint: no changes for <slug>" used to print over a dirty worktree,
# because artifacts/ files are deliberately not auto-staged. Observed live
# 2026-08-31: a findings file with three new sections sat uncommitted while the
# checkpoint reported success-shaped output.
#
# The scoping is correct and must NOT widen — auto-staging is how a checkpoint
# sweeps up a concurrent session's in-flight edits. So assert the notice, and
# assert the staging behaviour is unchanged in both directions.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

G() { git -c user.email=t@t.t -c user.name=t "$@"; }
# checkpoint.sh pulls and pushes, so the fixture needs a real upstream.
G init -q --bare "$TMP/origin.git"
G init -q --initial-branch=main "$TMP/wl"
cd "$TMP/wl"
G remote add origin "$TMP/origin.git"
mkdir -p people/tester/active people/tester/artifacts
cat > people/tester/active/thing.md <<'EOF'
---
slug: thing
owner: tester
status: in-progress
kind: impl
project: none
repos: []
last_updated: 2026-08-31
next_action: "x"
---

## Context

c

## Next

- [ ] x
EOF
printf '# findings\n' > people/tester/artifacts/thing-findings.md
G add -A && G commit -qm base
G push -q -u origin main

run() {  # -> OUT (stdout+stderr merged; the notice goes to stderr)
  OUT=$(WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
        bash "$ROOT/bin/checkpoint.sh" "$@" 2>&1)
}

# The first run normalizes and commits the task file, so the no-op path is only
# reached on a SECOND run — checking that here rather than assuming a clean tree
# is a no-op, which it is not.
run thing
run thing
printf '%s' "$OUT" | grep -q 'no changes' \
  && ck "second run reaches the no-op path" pass pass \
  || ck "second run reaches the no-op path" fail pass
printf '%s' "$OUT" | grep -q 'were not staged' \
  && ck "no-op over a clean tree raises no notice" fail pass \
  || ck "no-op over a clean tree raises no notice" pass pass

# Dirty artifact, untouched task file: the false green.
printf '\n## F1\n\nnew finding\n' >> people/tester/artifacts/thing-findings.md
run thing
printf '%s' "$OUT" | grep -q 'were not staged' \
  && ck "dirty artifact is named, not silently skipped" pass pass \
  || ck "dirty artifact is named, not silently skipped" fail pass
printf '%s' "$OUT" | grep -q 'thing-findings.md' \
  && ck "the notice names the actual file" pass pass \
  || ck "the notice names the actual file" fail pass
printf '%s' "$OUT" | grep -q -- '--include' \
  && ck "the notice says how to stage it" pass pass \
  || ck "the notice says how to stage it" fail pass
# The clone can be shared. A reader following --include literally would commit
# another session's in-flight edit under their own slug — the same sweep the
# notice exists to avoid, just hand-driven. Raised by a consuming session
# 2026-08-31 after that exact race happened between two of us.
printf '%s' "$OUT" | grep -q 'another session' \
  && ck "the notice warns the paths may not be yours" pass pass \
  || ck "the notice warns the paths may not be yours" fail pass

# The scope must NOT have widened: the artifact is still uncommitted.
if [ -n "$(G status --porcelain -- people/tester/artifacts/)" ]; then
  PASS=$((PASS+1)); printf '  PASS  notice did not auto-stage the artifact\n'
else FAIL=$((FAIL+1)); printf '  FAIL  ARTIFACT WAS AUTO-STAGED — scope widened\n'; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
