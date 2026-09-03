#!/usr/bin/env bash
# The post-commit cross-task lint must not go quiet when it did not run,
# and must say whose warnings it is counting.
#
# It swallowed a failed lint three ways: `2>/dev/null` dropped the error,
# `except Exception: pass` dropped the parse failure, and `|| true` covered
# the rest. A lint that crashed printed nothing -- byte-identical to a clean
# repo. Same shape as checkpoint.sh's soft gate, in a second file.
#
# Second, the counts had no scope. The hook fires after committing one file
# but lints every task in the repo, so "9 body-mention warning(s)" reads as
# "your commit caused 9". Observed 2026-09-03: all 9 were pre-existing and
# none named the file just committed.
#
# HOW THIS TESTS IT. The real hook file is COPIED into a scratch
# bin/git-hooks/ whose sibling ../lint.sh is a stub, because the hook derives
# SKILL_BIN from its own $0. The first draft of this fixture instead pasted
# the hook's python into the test and asserted against that -- it passed every
# case while the real hook was mutated to swallow errors again. A fixture that
# re-implements its subject tests the copy.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/bin/git-hooks/post-commit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

[ -f "$HOOK" ] || { echo "no hook at $HOOK" >&2; exit 1; }

# Run the REAL hook with a stubbed lint.sh next to it, inside a scratch repo.
run_hook() {
  local name="$1" lint_body="$2"
  local base="$TMP/$name"
  rm -rf "$base"
  mkdir -p "$base/bin/git-hooks" "$base/repo"
  cp "$HOOK" "$base/bin/git-hooks/post-commit"
  chmod +x "$base/bin/git-hooks/post-commit"
  printf '%s\n' "$lint_body" > "$base/bin/lint.sh"
  chmod +x "$base/bin/lint.sh"
  mkdir -p "$base/nohooks"
  ( cd "$base/repo"
    git init -q .
    git config user.email t@example.com
    git config user.name T
    # Isolate from any globally-configured core.hooksPath. This box has one
    # (a gitleaks pre-commit), and its banner landed in the captured output,
    # failing the control and the clean case. The control is what surfaced it.
    git config core.hooksPath "$base/nohooks"
    echo x > f.txt && git add -A && git commit -q -m seed
    # No .cache/cross-task.stamp, so the TTL gate lets the lint run.
    "$base/bin/git-hooks/post-commit" ) 2>&1
}

echo "=== 0. control: the hook reaches its lint at all ==="
# If the TTL gate or SKILL_BIN resolution kept the hook from running, case 4
# below -- "a clean lint prints nothing" -- would pass on a hook that never
# ran at all. The probe leaves a file rather than writing to stderr: the hook
# redirects lint's stderr into a temp file and only surfaces it on a parse
# failure, so a stderr marker is invisible on the success path (which is
# correct behaviour, and cost this control one revision to notice).
out="$(run_hook probe '#!/usr/bin/env bash
touch "$(dirname "$0")/../PROBE-REACHED"
echo "{\"total_files\": 1, \"total_errors\": 0, \"total_warnings\": 0, \"issues\": []}"')"
if [ -e "$TMP/probe/PROBE-REACHED" ]; then
  pass "the hook invokes its sibling lint.sh"
else
  fail "the hook never called lint.sh; nothing below proves anything: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 1. RED: a crashing lint is reported, not swallowed ==="
out="$(run_hook crash '#!/usr/bin/env bash
echo "lint.sh: ModuleNotFoundError: no module named yaml" >&2
exit 1')"
if grep -q 'lint SKIPPED' <<<"$out"; then
  pass "a crashing lint reports SKIPPED"
else
  fail "silent on a crashing lint: $(tr '\n' '/' <<<"$out")"
fi
if grep -q 'ModuleNotFoundError' <<<"$out"; then
  pass "the reason from lint.sh's stderr survives"
else
  fail "lint.sh's stderr was discarded: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 2. RED: a silent lint is reported ==="
out="$(run_hook silent '#!/usr/bin/env bash
exit 0')"
if grep -q 'lint SKIPPED' <<<"$out"; then
  pass "empty output reports SKIPPED, not clean"
else
  fail "an empty lint read as clean: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 3. RED: the counts name their scope ==="
out="$(run_hook counts '#!/usr/bin/env bash
echo "{\"total_files\": 370, \"total_errors\": 0, \"total_warnings\": 13, \"issues\": [{\"file\": \"a.md\", \"warnings\": [\"body mentions slug not in parent_slug\"]}]}"')"
if grep -q 'repo-wide' <<<"$out" && grep -q '370 task file' <<<"$out"; then
  pass "the warning count carries its scope and denominator"
else
  fail "counts without scope: $(tr '\n' '/' <<<"$out")"
fi
if grep -q 'of those are body-mention' <<<"$out"; then
  pass "body-mention is framed as a subset, not a new total"
else
  fail "body-mention count reads as its own total: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 4. GREEN: a genuinely clean repo stays quiet ==="
# Without this, every case above is satisfied by a hook that shouts always.
out="$(run_hook clean '#!/usr/bin/env bash
echo "{\"total_files\": 370, \"total_errors\": 0, \"total_warnings\": 0, \"issues\": []}"')"
if [ -z "$(tr -d '[:space:]' <<<"$out")" ]; then
  pass "a clean cross-task lint prints nothing"
else
  fail "noise on a clean repo: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 5. the hook never blocks a commit ==="
for name in crash silent counts; do
  set +e
  ( cd "$TMP/$name/repo" && "$TMP/$name/../$name/bin/git-hooks/post-commit" >/dev/null 2>&1 )
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "hook exited $rc in the '$name' case; it must never block"
done
[ "$FAIL" -eq 0 ] && pass "the hook exits 0 even when the lint is broken"

echo
[ "$FAIL" -eq 0 ] && echo "post-commit lint report: all cases passed" || echo "post-commit lint report: FAILURES above" >&2
exit "$FAIL"
