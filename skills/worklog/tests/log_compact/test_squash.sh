#!/usr/bin/env bash
# End-to-end test for bin/log-compact.sh --apply.
#
# Runs the FULL --apply path against a scratch clone of the real worklog repo,
# then asserts:
#   1. File contents at the rewritten HEAD match the file contents at the
#      pre-rewrite HEAD (no data loss).
#   2. Number of commits after = before - (sum over bursts of (members - 1)).
#   3. Each compacted-anchor commit's message starts with "<slug>: compacted".
#   4. Lint stays clean post-rewrite (0 errors / 0 warnings on the scratch repo).
#
# Why this exists: the previous filter-repo-based --apply implementation passed
# its own dry-run verification but then dropped 613 unrelated commits' file
# changes in production. Test-on-clone is the load-bearing gate that catches
# this class of bug BEFORE main is touched. Per Karpathy guideline 4: define
# success criteria, loop until verified.
#
# Usage:
#   tests/log_compact/test_squash.sh            # uses the current repo
#   SOURCE=/path/to/repo tests/log_compact/test_squash.sh
#
# Run BEFORE every bin/log-compact.sh --apply on real main.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t log-compact-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
TEST_ORIGIN="$SCRATCH_ROOT/origin.git"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Test setup ==="
echo "Source repo: $SOURCE"
echo "Scratch:     $SCRATCH"
echo "Test origin: $TEST_ORIGIN (isolated bare repo; real origin not touched)"
echo ""

# Bare repo to act as origin for the test (so --apply's pushes go nowhere harmful).
git clone -q --bare "$SOURCE" "$TEST_ORIGIN"

# Working clone, with origin reconfigured to the bare repo.
git clone -q "$TEST_ORIGIN" "$SCRATCH"
cd "$SCRATCH"
git config user.email "test@example.com"
git config user.name "log-compact-test"

# Capture the pre-rewrite HEAD's file tree as a fingerprint.
PRE_SHA="$(git rev-parse HEAD)"
PRE_COUNT="$(git rev-list --count HEAD)"
PRE_FINGERPRINT="$(git ls-tree -r HEAD | sort | sha256sum | awk '{print $1}')"
echo "Pre:  HEAD=$PRE_SHA  commits=$PRE_COUNT  tree-fingerprint=$PRE_FINGERPRINT"
echo ""

# Dry-run first to capture expected counts.
echo "=== Dry-run ==="
WORKLOG_NO_LINT=1 WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/log-compact.sh" > /tmp/dryrun-out 2>&1 || cat /tmp/dryrun-out
cat /tmp/dryrun-out
EXPECTED_DROPPED="$(grep -E '^bursts:' /tmp/dryrun-out | awk '{print $NF}')"
EXPECTED_BURSTS="$(grep -E '^bursts:' /tmp/dryrun-out | awk '{print $2}')"
EXPECTED_POST_COUNT=$((PRE_COUNT - EXPECTED_DROPPED + EXPECTED_BURSTS))
# dropped = total_burst_members - num_bursts ⇒ post = pre - dropped + bursts
echo "Expected post-rewrite commits = $PRE_COUNT - $EXPECTED_DROPPED + $EXPECTED_BURSTS = $EXPECTED_POST_COUNT"
echo ""

echo "=== Apply ==="
# WORKLOG_NO_HOOK / WORKLOG_NO_LINT skip the post-commit cross-task lint and
# pre-commit hooks for the test (the rebase produces hundreds of intermediate
# commits; running hooks on each is slow and not what we're testing).
WORKLOG_NO_LINT=1 WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/log-compact.sh" --apply 2>&1 | tail -10
echo ""

# Post-rewrite assertions.
POST_SHA="$(git rev-parse HEAD)"
POST_COUNT="$(git rev-list --count HEAD)"
POST_FINGERPRINT="$(git ls-tree -r HEAD | sort | sha256sum | awk '{print $1}')"
echo "Post: HEAD=$POST_SHA  commits=$POST_COUNT  tree-fingerprint=$POST_FINGERPRINT"
echo ""

PASS=1

# Assertion 1: file contents at HEAD match pre-rewrite.
if [[ "$PRE_FINGERPRINT" == "$POST_FINGERPRINT" ]]; then
  echo "✓ tree fingerprint matches (no file content lost)"
else
  echo "✗ FAIL: tree fingerprint changed — files differ"
  echo "  Compare in $SCRATCH: git diff $PRE_SHA HEAD"
  PASS=0
fi

# Assertion 2: commit count matches expected.
if [[ "$POST_COUNT" -eq "$EXPECTED_POST_COUNT" ]]; then
  echo "✓ commit count matches expected ($POST_COUNT)"
else
  echo "✗ FAIL: commit count expected $EXPECTED_POST_COUNT, got $POST_COUNT"
  PASS=0
fi

# Assertion 3: number of compacted-anchor commits = bursts.
COMPACTED_COUNT="$(git log --oneline | grep -c ': compacted ' || true)"
if [[ "$COMPACTED_COUNT" -eq "$EXPECTED_BURSTS" ]]; then
  echo "✓ found $COMPACTED_COUNT compacted-anchor commits as expected"
else
  echo "✗ FAIL: expected $EXPECTED_BURSTS compacted-anchor commits, found $COMPACTED_COUNT"
  PASS=0
fi

# Assertion 4: lint clean.
if WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/lint.sh" --cross-task 2>&1 | head -1 | grep -q '0 errors, 0 warnings'; then
  echo "✓ lint stays clean post-rewrite"
else
  echo "✗ FAIL: lint regression after rewrite"
  WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/lint.sh" --cross-task 2>&1 | head -10
  PASS=0
fi

if [[ "$PASS" -eq 1 ]]; then
  echo ""
  echo "ALL ASSERTIONS PASSED. Scratch: $SCRATCH_ROOT"
  trap - ERR
  exit 0
else
  echo ""
  echo "FAILURES ABOVE. Scratch left at $SCRATCH_ROOT for debugging."
  trap - ERR
  exit 1
fi
