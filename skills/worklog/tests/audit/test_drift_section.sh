#!/usr/bin/env bash
# audit.sh's drift section must not report "(clean)" over a corpus it never read.
#
# The section printed "  (clean)" whenever lint returned no issues. A lint that
# scanned zero task files also returns no issues, so running audit.sh against
# the wrong clone -- or with WORKLOG_REPO pointing somewhere empty -- produced
# a clean bill of health for a corpus that was never opened. "Nothing wrong
# here" and "nothing here" printed the same line.
#
# audit.sh deliberately always exits 0 ("a report, not a gate"), so the
# distinction has to live in what the section PRINTS. These cases assert on
# stdout, not on the exit code.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

unset WORKLOG_REPO WORKLOG_LDAP || true

REPO="$TMP/repo"
mkdir -p "$REPO/people/tester/active" "$REPO/people/tester/archive"
cd "$REPO"
git init -q .
git config user.email t@example.com
git config user.name T
cat > people/tester/active/t.md <<'EOF'
---
slug: t
kind: impl
status: in-progress
project: none
last_updated: 2026-09-01
next_action: go
repos: [x]
---

## Context
Body.

## Next
- [ ] go
EOF
git add -A
git commit -q -m seed

# A private bin/ so lint.sh can be stubbed without touching the tree under test.
stub_lint() {
  local dest="$TMP/bin-$1"
  rm -rf "$dest"
  cp -R "$ROOT/bin" "$dest"
  printf '%s\n' "$2" > "$dest/lint.sh"
  chmod +x "$dest/lint.sh"
  printf '%s' "$dest"
}

drift() {
  WORKLOG_REPO="$REPO" WORKLOG_LDAP=tester \
    "$1/audit.sh" --section=drift 2>&1 || true
}

echo "=== 1. RED: a zero-file scan is not clean ==="
bin="$(stub_lint zero '#!/usr/bin/env bash
echo "{\"total_files\": 0, \"files_with_issues\": 0, \"issues\": []}"')"
out="$(drift "$bin")"
if grep -q '(clean' <<<"$out"; then
  fail "a zero-file scan reported clean: $(tr '\n' '/' <<<"$out")"
else
  pass "a zero-file scan is not reported as clean"
fi
if grep -q 'no task files scanned' <<<"$out"; then
  pass "the empty scan says so explicitly"
else
  fail "no explanation for the empty scan: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 2. RED: a report with no scanned count is 'unavailable' ==="
bin="$(stub_lint nocount '#!/usr/bin/env bash
echo "{\"issues\": []}"')"
out="$(drift "$bin")"
if grep -q 'lint unavailable' <<<"$out"; then
  pass "a report without total_files falls through to (lint unavailable)"
else
  fail "JSON without total_files was accepted: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 3. GREEN: a real clean scan says clean AND how much it read ==="
# The control. Cases 1 and 2 are both satisfied by a section that never says
# "clean" at all, which would make the whole report useless.
bin="$(stub_lint clean '#!/usr/bin/env bash
echo "{\"total_files\": 7, \"files_with_issues\": 0, \"total_errors\": 0, \"total_warnings\": 0, \"issues\": []}"')"
out="$(drift "$bin")"
if grep -q '(clean' <<<"$out" && grep -q '7 file' <<<"$out"; then
  pass "a real clean scan reports clean with its scanned count"
else
  fail "clean verdict lost or countless: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 4. GREEN: real findings still surface ==="
bin="$(stub_lint findings '#!/usr/bin/env bash
echo "{\"total_files\": 3, \"total_errors\": 1, \"total_warnings\": 1, \"issues\": [{\"file\": \"a.md\", \"errors\": [\"boom-error\"], \"warnings\": [\"boom-warn\"]}]}"')"
out="$(drift "$bin")"
if grep -q 'ERROR   a.md: boom-error' <<<"$out" && grep -q 'warn    a.md: boom-warn' <<<"$out"; then
  pass "errors and warnings still print"
else
  fail "findings lost: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 5. a crashing lint is still reported unavailable ==="
bin="$(stub_lint crash '#!/usr/bin/env bash
echo "lint: boom" >&2
exit 1')"
out="$(drift "$bin")"
if grep -q 'lint unavailable' <<<"$out"; then
  pass "a crashing lint reports unavailable"
else
  fail "crashing lint was silent: $(tr '\n' '/' <<<"$out")"
fi

echo "=== 6. audit stays a report: exit 0 even when the section cannot run ==="
bin="$(stub_lint crash2 '#!/usr/bin/env bash
exit 1')"
set +e
WORKLOG_REPO="$REPO" WORKLOG_LDAP=tester "$bin/audit.sh" --section=drift >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  pass "audit.sh still exits 0 (a report, not a gate)"
else
  fail "audit.sh exited $rc; its documented contract is always 0"
fi

echo "=== 7. the (none) verdicts say none OF WHAT ==="
# Same shape as case 1, one section over. "No blocked tasks" and "the index
# holds no tasks at all" both produced a bare "(none)".
section() {
  WORKLOG_REPO="$REPO" WORKLOG_LDAP=tester \
    "$ROOT/bin/audit.sh" --section="$1" 2>&1 || true
}
for sec in blocked in-review; do
  out="$(section "$sec")"
  if grep -qE '\(none of [0-9]+ active tasks\)' <<<"$out"; then
    pass "$sec reports the corpus size with its (none)"
  elif grep -q '(none)' <<<"$out"; then
    fail "$sec printed a bare (none): $(tr '\n' '/' <<<"$out")"
  else
    fail "$sec produced no (none) verdict at all: $(tr '\n' '/' <<<"$out")"
  fi
done

echo "=== 8. the corpus size is the real one, not a constant ==="
# A count hard-wired to 0 -- or to any constant -- would satisfy case 7. The
# scratch repo holds exactly one active task.
out="$(section blocked)"
if grep -q '(none of 1 active tasks)' <<<"$out"; then
  pass "the count matches the one seeded active task"
else
  fail "expected a count of 1: $(tr '\n' '/' <<<"$out")"
fi

echo
[ "$FAIL" -eq 0 ] && echo "audit drift section: all cases passed" || echo "audit drift section: FAILURES above" >&2
exit "$FAIL"
