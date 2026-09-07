#!/usr/bin/env bash
# Case 1c from test_plan.md: a git repo with no origin remote.
#
# This lives in its own file rather than in test_pr_review_bin.sh because the
# runner globs skills/*/tests/test_*.sh, so a new fixture is wired up by
# existing, and a separate file cannot collide with concurrent edits to the
# main fixture in this shared checkout.
#
# The contract under test is the one that matters for a wrong answer: an
# unresolvable origin must FAIL LOUDLY, not classify as some default forge.
# A repo with no origin is indistinguishable from an unreachable one at the
# call site, so a silent default here would hand the caller a confident wrong
# forge instead of an error.
#
# Exit: 0 all cases pass, 1 otherwise.

set -uo pipefail

BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A real repo, initialised, with no remote configured at all.
mk_no_origin() { mkdir -p "$1" && git -C "$1" init -q 2>/dev/null; }

# A repo whose only remote is named something other than origin. This is the
# case a `git remote get-url origin` guard catches but a "first remote wins"
# implementation would silently misread.
mk_other_remote() {
  mkdir -p "$1" && git -C "$1" init -q 2>/dev/null
  git -C "$1" remote add upstream "git@github.com:acme/widget.git"
}

echo "=== 1c. a repo with no origin remote exits 2, and says why ==="

mk_no_origin "$TMP/bare-init"
out="$("$BIN/detect-forge.sh" --repo "$TMP/bare-init" 2>&1 >/dev/null)"; st=$?
[[ "$st" -eq 2 ]] \
  && pass "no origin exits 2" \
  || fail "no origin must exit 2, got $st"

# Not just "nonzero": the message must name the missing remote, or the caller
# cannot tell this apart from a bad --repo path (which also exits 2).
[[ "$out" == *origin* ]] \
  && pass "the error names the origin remote" \
  || fail "the error must name origin, got '$out'"

# The loud-failure half of the contract: nothing may reach stdout. A consumer
# reads stdout with `IFS=$'\t' read -r forge slug cli`, so a stray line here
# becomes a forge name.
sout="$("$BIN/detect-forge.sh" --repo "$TMP/bare-init" 2>/dev/null)"
[[ -z "$sout" ]] \
  && pass "nothing is printed to stdout" \
  || fail "stdout must stay empty, got '$sout'"

echo "=== 1c-b. a non-origin remote is not silently adopted ==="

mk_other_remote "$TMP/upstream-only"
out="$("$BIN/detect-forge.sh" --repo "$TMP/upstream-only" 2>&1 >/dev/null)"; st=$?
sout="$("$BIN/detect-forge.sh" --repo "$TMP/upstream-only" 2>/dev/null)"
[[ "$st" -eq 2 && -z "$sout" ]] \
  && pass "an upstream-only repo exits 2 without classifying" \
  || fail "upstream-only must exit 2 with empty stdout, got rc=$st out='$sout'"

# Distinguish the two failures the plan lists as separate rows: 1a is a bad
# target (not a repo), 1c is a good target with no origin. Both exit 2, so the
# text is the only thing that separates them.
notrepo="$("$BIN/detect-forge.sh" --repo "$TMP/not-a-repo" 2>&1 >/dev/null)"
[[ "$notrepo" != "$out" ]] \
  && pass "a missing origin reads differently from a non-repo" \
  || fail "1a and 1c produce the same message: '$out'"

if [[ "$FAIL" -ne 0 ]]; then
  echo "pr-review no-origin: FAILURES above" >&2
  exit 1
fi
echo "pr-review no-origin: all cases pass"
