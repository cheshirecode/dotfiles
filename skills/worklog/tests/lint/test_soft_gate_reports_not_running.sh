#!/usr/bin/env bash
# checkpoint.sh's soft lint gate must distinguish "found nothing" from "never ran".
#
# The gate is deliberately non-blocking, and that stays true here. What changed
# is that it used to be non-blocking AND silent on its own failure: `|| true`
# dropped lint.sh's exit status, `2>/dev/null` dropped its error message, and
# the embedded python exited 0 on any parse failure. A lint.sh that crashed,
# lost a dependency, or printed nothing produced byte-identical checkpoint
# output to a genuinely clean task -- and the checkpoint then recorded the task
# as verified.
#
# Each case below drives the real bin/checkpoint.sh against a scratch repo with
# a stub lint.sh on a copied bin/, so the gate is exercised end to end rather
# than re-implemented here.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

unset WORKLOG_REPO WORKLOG_LDAP WORKLOG_NO_LINT || true

# One scratch worklog repo plus a private copy of bin/, so a stub lint.sh can
# be swapped in without touching the tree under test.
setup_repo() {
  local repo="$TMP/$1"
  mkdir -p "$repo/people/tester/active" "$repo/people/tester/archive"
  cd "$repo"
  git init -q .
  git config user.email tester@example.com
  git config user.name Tester
  cat > people/tester/active/gate-task.md <<'EOF'
---
slug: gate-task
kind: impl
status: in-progress
project: none
last_updated: 2026-01-01
next_action: Keep going
repos: [sample]
---

## Context
Body.

## Next
- [ ] Keep going
EOF
  git add -A
  git commit -q -m "seed"
  # Detached origin so checkpoint's push has somewhere harmless to go.
  git init -q --bare "$TMP/$1.git"
  git remote add origin "$TMP/$1.git"
  git push -q -u origin HEAD
  printf '%s' "$repo"
}

# Copy bin/ and replace lint.sh with the given stub body.
stub_bin() {
  local dest="$TMP/$1-bin"
  cp -R "$ROOT/bin" "$dest"
  printf '%s\n' "$2" > "$dest/lint.sh"
  chmod +x "$dest/lint.sh"
  printf '%s' "$dest"
}

run_checkpoint() {
  local repo="$1" bin="$2"
  cd "$repo"
  WORKLOG_REPO="$repo" WORKLOG_LDAP=tester \
    "$bin/checkpoint.sh" gate-task --next="moved $RANDOM" 2>&1 || true
}

echo "=== 1. RED: a lint.sh that crashes is reported, not swallowed ==="
repo="$(setup_repo crash)"
bin="$(stub_bin crash '#!/usr/bin/env bash
echo "lint.sh: ModuleNotFoundError: no module named yaml" >&2
exit 1')"
out="$(run_checkpoint "$repo" "$bin")"
if grep -q 'lint SKIPPED' <<<"$out"; then
  pass "crashing lint.sh reports SKIPPED"
else
  fail "crashing lint.sh was silent; output was: $(tr '\n' '/' <<<"$out")"
fi
if grep -q 'ModuleNotFoundError' <<<"$out"; then
  pass "the reason from lint.sh's stderr survives"
else
  fail "lint.sh's stderr was discarded; output was: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 2. RED: a lint.sh that prints nothing at all is reported ==="
repo="$(setup_repo silent)"
bin="$(stub_bin silent '#!/usr/bin/env bash
exit 0')"
out="$(run_checkpoint "$repo" "$bin")"
if grep -q 'lint SKIPPED' <<<"$out"; then
  pass "silent success is reported as SKIPPED, not clean"
else
  fail "an empty lint read as clean; output was: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 3. RED: valid JSON missing the scanned count is reported ==="
# The shape that makes checks 1 and 2 insufficient on their own: output that
# parses, has an empty "issues" list, and never scanned anything.
repo="$(setup_repo noscan)"
bin="$(stub_bin noscan '#!/usr/bin/env bash
echo "{\"issues\": []}"')"
out="$(run_checkpoint "$repo" "$bin")"
if grep -q 'lint SKIPPED' <<<"$out"; then
  pass "JSON without total_files is reported as SKIPPED"
else
  fail "a scanned-nothing report read as clean; output was: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 4. GREEN: a real clean lint stays quiet ==="
# Without this the three cases above would pass on a gate that shouts
# SKIPPED unconditionally.
repo="$(setup_repo clean)"
bin="$(stub_bin clean '#!/usr/bin/env bash
echo "{\"total_files\": 1, \"files_with_issues\": 0, \"total_errors\": 0, \"total_warnings\": 0, \"issues\": []}"')"
out="$(run_checkpoint "$repo" "$bin")"
if grep -q 'lint SKIPPED' <<<"$out"; then
  fail "a clean lint was reported as SKIPPED; output was: $(tr '\n' '/' <<<"$out")"
else
  pass "a clean lint stays quiet"
fi

echo "=== 5. GREEN: real findings still surface ==="
repo="$(setup_repo findings)"
bin="$(stub_bin findings '#!/usr/bin/env bash
echo "{\"total_files\": 1, \"issues\": [{\"file\": \"x.md\", \"errors\": [\"boom-error\"], \"warnings\": [\"boom-warning\"]}]}"')"
out="$(run_checkpoint "$repo" "$bin")"
if grep -q 'lint ERROR  boom-error' <<<"$out" && grep -q 'lint warn   boom-warning' <<<"$out"; then
  pass "errors and warnings still print"
else
  fail "findings were lost; output was: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 6. the gate stays soft: a broken lint never blocks the checkpoint ==="
repo="$(setup_repo soft)"
bin="$(stub_bin soft '#!/usr/bin/env bash
exit 3')"
cd "$repo"
set +e
WORKLOG_REPO="$repo" WORKLOG_LDAP=tester \
  "$bin/checkpoint.sh" gate-task --next="soft $RANDOM" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "checkpoint still exits 0 with a broken lint"
else
  fail "checkpoint exited $rc; the gate must stay non-blocking"
fi

echo
[ "$FAIL" -eq 0 ] && echo "soft lint gate: all cases passed" || echo "soft lint gate: FAILURES above" >&2
exit "$FAIL"
