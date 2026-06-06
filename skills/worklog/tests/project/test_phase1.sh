#!/usr/bin/env bash
# End-to-end test for `bin/project.sh` phase 1 (new + next, no mutex).
#
# Acceptance (from worklog-project-mode.md § Phase 1):
#   Create a 3-task project (A, B depends_on A, C depends_on B).
#   `project next` returns A. Archive A. `project next` returns B.
#   Archive B. `project next` returns C.
#
# Plus:
#   - lint accepts kind: project
#   - --dry-run does not write files
#   - duplicate child slug rejected
#   - missing --goal / --objective rejected
#
# Runs against a scratch clone so production worklog isn't touched.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t project-phase1-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Test setup ==="
# Bare upstream the scratch repo can safely push to.
git init -q --bare "$UPSTREAM"
git clone -q "$SOURCE" "$SCRATCH"
# Mirror uncommitted bin/ + lint changes from $SOURCE into the scratch clone so
# the test exercises the working tree, not the last committed tree.
rm -rf "$SCRATCH/bin"
cp -R "$SOURCE/bin" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
cd "$SCRATCH"
git remote set-url origin "$UPSTREAM"
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
git config user.email "testuser@example.com"
git config user.name "project-phase1-test"

LDAP="testuser"
printf '%s' "$LDAP" > "$TMPDIR/worklog-ldap-${USER}"
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"
# Disable hooks to keep the test focused on project.sh behavior.
export WORKLOG_NO_HOOK=1
export WORKLOG_SKIP_PROVENANCE=1
mkdir -p .cache; touch .cache/provenance-verified

echo ""
echo "=== Phase 1.1: lint accepts kind: project ==="
cat > "people/$LDAP/active/proj-x.md" <<'EOF'
---
slug: proj-x
status: draft
kind: project
repos: []
project: none
last_updated: 2026-05-12
next_action: "test"
---

## Context

test
EOF
"$WORKLOG_BIN/lint.sh" --file="people/$LDAP/active/proj-x.md" >/dev/null 2>&1 \
  && echo "  ✓ kind: project passes lint" \
  || { echo "FAIL: lint rejected kind: project"; "$WORKLOG_BIN/lint.sh" --file="people/$LDAP/active/proj-x.md"; exit 1; }
rm "people/$LDAP/active/proj-x.md"

echo ""
echo "=== Phase 1.2: --dry-run does not write files ==="
TASKS='[{"slug":"phase1-a"},{"slug":"phase1-b","depends_on":["phase1-a"]},{"slug":"phase1-c","depends_on":["phase1-b"]}]'
echo "$TASKS" | "$WORKLOG_BIN/project.sh" new phase1-proj \
  --goal "Test phase 1" \
  --objective "Verify project new + next" \
  --dry-run >/dev/null
[[ ! -e "people/$LDAP/active/phase1-proj.md" ]] || { echo "FAIL: dry-run wrote project file"; exit 1; }
[[ ! -e "people/$LDAP/active/phase1-a.md" ]]    || { echo "FAIL: dry-run wrote child file"; exit 1; }
echo "  ✓ --dry-run wrote nothing to disk"

echo ""
echo "=== Phase 1.3: missing --goal rejected ==="
if echo "$TASKS" | "$WORKLOG_BIN/project.sh" new bad-proj --objective "x" 2>/dev/null; then
  echo "FAIL: expected exit-nonzero on missing --goal"; exit 1
fi
echo "  ✓ missing --goal rejected"

echo ""
echo "=== Phase 1.4: duplicate child slug rejected ==="
DUPE='[{"slug":"dup-a"},{"slug":"dup-a"}]'
if echo "$DUPE" | "$WORKLOG_BIN/project.sh" new bad-proj --goal=x --objective=x 2>/dev/null; then
  echo "FAIL: expected exit-nonzero on duplicate child slug"; exit 1
fi
echo "  ✓ duplicate child slug rejected"

echo ""
echo "=== Phase 1.5: project new creates project + children ==="
echo "$TASKS" | "$WORKLOG_BIN/project.sh" new phase1-proj \
  --goal "Test phase 1" \
  --objective "Verify project new + next"
[[ -f "people/$LDAP/active/phase1-proj.md" ]] || { echo "FAIL: project file not created"; exit 1; }
for s in phase1-a phase1-b phase1-c; do
  [[ -f "people/$LDAP/active/$s.md" ]] || { echo "FAIL: child $s not created"; exit 1; }
done
echo "  ✓ project + 3 children created"

# Sanity: project file has kind: project, parent children have parent_slug.
grep -q '^kind: project$' "people/$LDAP/active/phase1-proj.md" || { echo "FAIL: project missing kind: project"; exit 1; }
grep -q '^parent_slug: phase1-proj$' "people/$LDAP/active/phase1-b.md" || { echo "FAIL: child missing parent_slug"; exit 1; }
echo "  ✓ frontmatter looks right (kind + parent_slug)"

echo ""
echo "=== Phase 1.6: project next walks A → B → C as deps archive ==="
out="$("$WORKLOG_BIN/project.sh" next phase1-proj)"
[[ "$out" == "phase1-a" ]] || { echo "FAIL: expected phase1-a, got '$out'"; exit 1; }
echo "  ✓ first next = phase1-a"

"$WORKLOG_BIN/archive.sh" phase1-a --reason=shipped >/dev/null
out="$("$WORKLOG_BIN/project.sh" next phase1-proj)"
[[ "$out" == "phase1-b" ]] || { echo "FAIL: expected phase1-b, got '$out'"; exit 1; }
echo "  ✓ after archive A, next = phase1-b"

"$WORKLOG_BIN/archive.sh" phase1-b --reason=shipped >/dev/null
out="$("$WORKLOG_BIN/project.sh" next phase1-proj)"
[[ "$out" == "phase1-c" ]] || { echo "FAIL: expected phase1-c, got '$out'"; exit 1; }
echo "  ✓ after archive B, next = phase1-c"

"$WORKLOG_BIN/archive.sh" phase1-c --reason=shipped >/dev/null
if "$WORKLOG_BIN/project.sh" next phase1-proj 2>/dev/null; then
  echo "FAIL: expected exit-nonzero when all tasks archived"; exit 1
fi
echo "  ✓ after archive C, next exits non-zero (nothing left)"

echo ""
echo "All phase-1 assertions passed."
trap - ERR
rm -rf "$SCRATCH_ROOT"
