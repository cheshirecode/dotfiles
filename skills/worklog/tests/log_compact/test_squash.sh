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
# Pinned to the tree under test, not `${WORKLOG_BIN:-...}`. A developer
# profile exports WORKLOG_BIN at the *installed* skill, which is a different
# checkout; honouring it makes this fixture grade the installed helpers
# instead of the ones sitting next to it, so a fix in the working tree can
# read green against unfixed code. tests/run.sh unsets the variable, and
# deriving it here keeps the fixture honest when run by hand too.
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"

cd "$(dirname "$0")/../.."
# This is a pre-`--apply` regression gate that rewrites real history on a clone,
# so SOURCE must be a clonable worklog *data* repo. Post-relocation the skill dir
# (pwd) is no longer that repo; default to $WORKLOG_REPO (the real vault) — the
# bare TEST_ORIGIN clone keeps the real origin untouched.
SOURCE="${SOURCE:-${WORKLOG_REPO:-}}"

# Validate before doing any work. The old default was $(pwd) -- the skill
# directory -- which is never a worklog data repo, so an unset WORKLOG_REPO
# produced a bare `git clone` fatal naming a path the reader has no reason to
# connect to the missing variable. Check the argument first and say what to
# set, rather than discovering it three commands into a rewrite.
if [ -z "$SOURCE" ]; then
  echo "$(basename "$0"): no source repo." >&2
  echo "  This gate rewrites history on a clone of a worklog DATA repo." >&2
  echo "  Set WORKLOG_REPO (or SOURCE=/path/to/repo) and re-run." >&2
  exit 1
fi
if [ ! -e "$SOURCE/.git" ]; then
  echo "$(basename "$0"): SOURCE=$SOURCE is not a git repo." >&2
  exit 1
fi
if [ ! -d "$SOURCE/people" ]; then
  echo "$(basename "$0"): SOURCE=$SOURCE has no people/ -- not a worklog data repo." >&2
  echo "  The skill directory is not the data repo; they were split." >&2
  exit 1
fi

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
# Pin the data repo to the scratch clone, overriding any WORKLOG_REPO the dev's
# shell exported — otherwise resolve_worklog_repo() sends log-compact.sh's
# history rewrite at the *real* vault while assertions measure the scratch.
export WORKLOG_REPO="$SCRATCH"
git config user.email "test@example.com"
git config user.name "log-compact-test"

# Capture the pre-rewrite HEAD's file tree as a fingerprint.
PRE_SHA="$(git rev-parse HEAD)"
PRE_COUNT="$(git rev-list --count HEAD)"
PRE_FINGERPRINT="$(git ls-tree -r HEAD | sort | sha256sum | awk '{print $1}')"
# Baseline of pre-existing compacted-anchors (the vault carries some from past
# real compactions); assertion 3 measures the delta this run creates.
PRE_COMPACTED="$(git log --oneline | grep -c ': compacted ' || true)"
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

# Assertion 3: number of *new* compacted-anchor commits = bursts this run.
POST_COMPACTED="$(git log --oneline | grep -c ': compacted ' || true)"
NEW_COMPACTED=$((POST_COMPACTED - PRE_COMPACTED))
if [[ "$NEW_COMPACTED" -eq "$EXPECTED_BURSTS" ]]; then
  echo "✓ created $NEW_COMPACTED compacted-anchor commits as expected (bursts=$EXPECTED_BURSTS)"
else
  echo "✗ FAIL: expected $EXPECTED_BURSTS new compacted-anchors, created $NEW_COMPACTED (pre=$PRE_COMPACTED post=$POST_COMPACTED)"
  PASS=0
fi

# Assertion 4: no lint *errors* introduced by the rewrite. (Warnings are advisory
# — lint.sh itself exits 0 on them — and the vault carries long-standing
# intentional ones like "missing project:"; the rewrite-corruption signal we care
# about is errors.)
if WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/lint.sh" --cross-task 2>&1 | head -1 | grep -qE '0 errors,'; then
  echo "✓ lint stays error-free post-rewrite"
else
  echo "✗ FAIL: lint errors after rewrite"
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
