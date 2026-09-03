#!/usr/bin/env bash
# related-search.sh is the pre-write prior-art probe. Its whole value is that
# a keyword with no hits and a keyword that was never searched look different.
#
# Both used to look the same. Under `set -euo pipefail`:
#   - `grep -lr ... | head` returns grep's exit 1 on no matches, which killed
#     the loop, so `related-search.sh nosuchword widget` printed the header for
#     the first keyword and stopped. The second keyword -- with real prior art
#     -- was never searched, and nothing said so.
#   - `"$here"/*/active/*.md` is passed through literally when it matches
#     nothing, so any namespace without an archive/ yet made awk fail. A
#     successful --projects listing then exited 2, which is this script's own
#     documented usage-error code.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/bin/related-search.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

unset WORKLOG_LDAP || true

# A namespace with active/ populated and archive/ empty -- the state every new
# namespace is in, and the one that broke the globs.
REPO="$TMP/repo"
mkdir -p "$REPO/people/tester/active" "$REPO/people/tester/archive"
cd "$REPO"
git init -q .
cat > people/tester/active/t.md <<'EOF'
---
slug: t
project: alpha
---

mentions widget here
EOF
export WORKLOG_REPO="$REPO"

run() { set +e; OUT="$("$SCRIPT" "$@" 2>&1)"; RC=$?; set -e; }

echo "=== 1. RED: an unmatched keyword must not abort the later ones ==="
run nosuchword widget
if [ "$RC" -eq 0 ]; then
  pass "exit 0 with a keyword that has no matches"
else
  fail "exited $RC on a no-match keyword; output: $(tr '\n' '/' <<<"$OUT")"
fi
if grep -q '=== widget ===' <<<"$OUT"; then
  pass "the second keyword was still searched"
else
  fail "the probe stopped at the first keyword; output: $(tr '\n' '/' <<<"$OUT")"
fi
if grep -q 't.md' <<<"$OUT"; then
  pass "the second keyword's prior art was reported"
else
  fail "prior art for 'widget' was lost; output: $(tr '\n' '/' <<<"$OUT")"
fi

echo "=== 2. a searched-and-empty keyword says so ==="
# "No output under the header" is what a keyword that was never reached also
# looks like. The verdict has to be printed, not inferred from silence.
if grep -q 'no matches' <<<"$OUT"; then
  pass "an empty result is stated, not left blank"
else
  fail "no-match printed nothing; output: $(tr '\n' '/' <<<"$OUT")"
fi

echo "=== 3. RED: --projects works with an empty archive/ ==="
run --projects
if [ "$RC" -eq 0 ]; then
  pass "--projects exits 0"
else
  fail "--projects exited $RC (2 is this script's usage-error code)"
fi
if [ "$OUT" = "alpha" ]; then
  pass "--projects listed the project"
else
  fail "--projects printed '$OUT', expected 'alpha'"
fi

echo "=== 4. GREEN: a real usage error still exits 2 ==="
# Without this, cases 1 and 3 would pass on a script that had simply stopped
# reporting failure at all.
run
if [ "$RC" -eq 2 ]; then
  pass "no arguments still exits 2"
else
  fail "no arguments exited $RC, expected 2"
fi

echo "=== 5. GREEN: a matching keyword still finds its file ==="
run widget
if [ "$RC" -eq 0 ] && grep -q 't.md' <<<"$OUT"; then
  pass "a matching keyword reports the file"
else
  fail "match lost: rc=$RC output: $(tr '\n' '/' <<<"$OUT")"
fi

echo "=== 6. a repo with no task directories fails loudly ==="
# The scope list is what makes cases 1-3 work; if it could be silently empty,
# every keyword would report "(no matches)" and the probe would look clean on
# a repo it never read.
BARE="$TMP/bare"
mkdir -p "$BARE/people"
(cd "$BARE" && git init -q .)
set +e
OUT="$(WORKLOG_REPO="$BARE" "$SCRIPT" widget 2>&1)"; RC=$?
set -e
if [ "$RC" -ne 0 ] && grep -qi 'no active/ or archive/' <<<"$OUT"; then
  pass "an unsearchable repo is an error, not a clean probe"
else
  fail "unsearchable repo gave rc=$RC output: $(tr '\n' '/' <<<"$OUT")"
fi

echo
[ "$FAIL" -eq 0 ] && echo "related-search: all cases passed" || echo "related-search: FAILURES above" >&2
exit "$FAIL"
