#!/usr/bin/env bash
# log-compact.sh must not demand a tool it no longer calls.
#
# It carried a hard preflight -- exit 2, "git-filter-repo not installed" --
# for a dependency its own code comment says was removed on 2026-04-27, when
# the filter-repo --apply path was replaced by `git rebase -i --root`. The
# rule stayed correct-looking while its stated reason quietly became false.
#
# The cost was not cosmetic. The preflight runs before --dry-run too, so on
# any machine without git-filter-repo the script refused every mode, and
# tests/log_compact/test_squash.sh -- the end-to-end gate that exists BECAUSE
# an earlier --apply silently dropped 613 commits' file changes -- could never
# execute. A regression gate blocked by a dependency check for deleted code is
# a check that cannot fail and a gate that cannot run.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

# A mirror of the real PATH with exactly one tool removed, so the absence
# case is exercised on machines that DO have git-filter-repo installed.
# Hand-listing the tools to link instead produced a PATH so thin that
# log-compact.sh died at rc=127 before reaching any preflight -- and the
# "not blocked by the dependency" assertion passed on a run that never got
# there. Mirror everything, subtract the one thing under test.
STUB="$TMP/path"
mkdir -p "$STUB"
IFS=':' read -ra PATH_DIRS <<< "$PATH"
for d in "${PATH_DIRS[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    [ -x "$f" ] && [ ! -d "$f" ] || continue
    base="${f##*/}"
    [ -e "$STUB/$base" ] || ln -sf "$f" "$STUB/$base"
  done
done
rm -f "$STUB/git-filter-repo"

# Controls on the stub PATH itself. Without these, every assertion below is
# satisfied by a PATH too broken to run anything.
if PATH="$STUB" git --version >/dev/null 2>&1; then
  pass "stub PATH can still run git"
else
  fail "stub PATH cannot run git; nothing below would prove anything"
fi
if PATH="$STUB" command -v git-filter-repo >/dev/null 2>&1; then
  fail "the stub PATH leaked git-filter-repo; this test would prove nothing"
else
  pass "stub PATH has no git-filter-repo"
fi

echo "=== 1. RED: log-compact.sh runs with no git-filter-repo on PATH ==="
REPO="$TMP/repo"
mkdir -p "$REPO/people/tester/active"
cd "$REPO"
git init -q .
git config user.email t@example.com
git config user.name T
printf -- '---\nslug: t\nstatus: in-progress\n---\n\n## Context\nx\n' \
  > people/tester/active/t.md
git add -A
git commit -q -m "t: checkpoint"

set +e
OUT="$(PATH="$STUB" WORKLOG_REPO="$REPO" "$BIN/log-compact.sh" 2>&1)"
RC=$?
set -e
if grep -q 'git-filter-repo not installed' <<<"$OUT"; then
  fail "still blocked by the stale dependency: $(tr '\n' '/' <<<"$OUT")"
elif [ "$RC" -eq 2 ]; then
  fail "dry run exited 2 (preflight refusal): $(tr '\n' '/' <<<"$OUT")"
elif [ "$RC" -eq 127 ]; then
  fail "rc=127: the run died on a missing command before reaching the work"
elif [ "$RC" -ne 0 ]; then
  fail "dry run exited $RC: $(tr '\n' '/' <<<"$OUT")"
else
  pass "the dry run exits 0 with no git-filter-repo on PATH"
fi
# "It did not refuse" is not "it ran". Require output only a completed
# dry-run produces, so a run that died early cannot satisfy this case.
if grep -q 'DRY RUN' <<<"$OUT"; then
  pass "the dry-run reached its plan output"
else
  fail "no DRY RUN banner; the script never reached the work: $(tr '\n' '/' <<<"$OUT")"
fi

echo "=== 2. the source no longer claims or checks the dependency ==="
if grep -q 'command -v git-filter-repo' "$BIN/log-compact.sh"; then
  fail "the git-filter-repo preflight is back in log-compact.sh"
else
  pass "no git-filter-repo preflight in log-compact.sh"
fi
if grep -qE '^# Requires: git-filter-repo' "$BIN/log-compact.sh"; then
  fail "the header still requires git-filter-repo"
else
  pass "the header no longer requires git-filter-repo"
fi

echo "=== 3. GREEN: cache-purge.sh still requires it, because it calls it ==="
# Without this control, checks 1 and 2 would also pass on a repo where
# someone had simply deleted every mention of git-filter-repo, including from
# the one script that genuinely runs it.
if grep -q 'git filter-repo --force --invert-paths' "$BIN/cache-purge.sh"; then
  pass "cache-purge.sh still invokes git filter-repo"
else
  fail "cache-purge.sh no longer invokes it -- retarget this control"
fi

echo "=== 4. the removal was not premature: nothing runs it in log-compact ==="
# The reason the preflight was safe to drop, asserted rather than remembered.
if grep -nE '(^|[^-])git[ -]filter-repo' "$BIN/log-compact.sh" | grep -v '^[0-9]*:#' | grep -q .; then
  fail "log-compact.sh does invoke git-filter-repo; restore the preflight"
else
  pass "log-compact.sh invokes git-filter-repo nowhere outside comments"
fi

echo
[ "$FAIL" -eq 0 ] && echo "stale dependency: all cases passed" || echo "stale dependency: FAILURES above" >&2
exit "$FAIL"
