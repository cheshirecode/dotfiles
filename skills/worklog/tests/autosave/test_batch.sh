#!/usr/bin/env bash
# Tests autosave namespace scoping, amend batching, Worklog-Paths trailer, flush.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

SCRATCH_ROOT="$(mktemp -d -t autosave-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

git init -q --bare "$UPSTREAM"
git init -q "$SCRATCH"
cp -R "$WORKLOG_BIN" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
chmod +x "$SCRATCH"/bin/*.sh
cd "$SCRATCH"
export WORKLOG_REPO="$SCRATCH"
export WORKLOG_LDAP="alice"
export WORKLOG_SKIP_PROVENANCE=1
export WORKLOG_NO_HOOK=1
unset WORKLOG_AUTOSAVE_WIDE
git config user.email "alice@example.com"
git config user.name "autosave-test"
git remote add origin "$UPSTREAM"
mkdir -p people/alice/active people/alice/archive people/bob/active .cache
touch people/alice/archive/.gitkeep
touch .cache/provenance-verified
git add -A && git -c commit.gpgsign=false commit -q -m "seed" --no-verify
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

fail() { echo "FAIL: $*"; exit 1; }

cat > people/alice/active/task-a.md <<'EOF'
---
slug: task-a
status: draft
kind: impl
last_updated: 2026-06-08
next_action: "test"
---

## Context
alice
EOF

cat > people/bob/active/task-b.md <<'EOF'
---
slug: task-b
status: draft
kind: impl
last_updated: 2026-06-08
next_action: "test"
---

## Context
bob
EOF

echo "=== 1. namespace scope: only people/alice/ ==="
echo "alice-only" >> people/alice/active/task-a.md
echo "bob-only" >> people/bob/active/task-b.md
"$SCRATCH/bin/autosave.sh" --trigger=manual
BODY="$(git log -1 --format=%B)"
echo "$BODY" | grep -q "Worklog-Paths: people/alice/active/task-a.md" \
  || fail "Worklog-Paths missing alice path"
echo "$BODY" | grep -q "people/bob" && fail "bob path should not be in autosave body"
git show --name-only --format= | grep -q "people/bob" && fail "bob file should not be committed"
git push -q origin main
echo "  ✓ namespace scope"

echo "=== 2. amend batching: second autosave amends unpushed head ==="
echo "round-two" >> people/alice/active/task-a.md
"$SCRATCH/bin/autosave.sh" --trigger=pre-compact
COUNT_AFTER_FIRST="$(git rev-list --count HEAD)"
# Simulate unpushed autosave (debounced push): origin lags HEAD by one autosave.
git update-ref "refs/remotes/origin/main" "$(git rev-parse HEAD~1)"
echo "round-three" >> people/alice/active/task-a.md
"$SCRATCH/bin/autosave.sh" --trigger=session-end
COUNT_AFTER_SECOND="$(git rev-list --count HEAD)"
(( COUNT_AFTER_SECOND == COUNT_AFTER_FIRST )) \
  || fail "expected amend (count $COUNT_AFTER_FIRST -> $COUNT_AFTER_SECOND)"
git log -1 --format=%s | grep -q '^autosave:' || fail "head should stay autosave"
echo "  ✓ amend batching"

echo "=== 3. autosave-flush pushes pending commits ==="
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse origin/main)"
[[ "$LOCAL" != "$REMOTE" ]] || fail "expected local ahead before flush"
"$SCRATCH/bin/autosave-flush.sh"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "flush should push"
echo "  ✓ flush"

echo "=== 4. WORKLOG_AUTOSAVE_WIDE=1 includes other namespaces ==="
echo "wide-bob" >> people/bob/active/task-b.md
WORKLOG_AUTOSAVE_WIDE=1 "$SCRATCH/bin/autosave.sh" --trigger=manual
git diff-tree --no-commit-id --name-only -r HEAD | grep -q "people/bob/active/task-b.md" \
  || fail "wide mode should include bob"
echo "  ✓ wide mode"

echo ""
echo "=== autosave test PASS ==="
