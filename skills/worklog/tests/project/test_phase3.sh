#!/usr/bin/env bash
# Phase 3 test: verify, list, stacking-strategy parser, Cursor session fallback.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t project-phase3-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Setup ==="
git init -q --bare "$UPSTREAM"
# Fresh scratch data repo (see test_phase1.sh for why we init rather than clone
# $SOURCE, and why WORKLOG_REPO must be pinned to the scratch).
git init -q "$SCRATCH"
cp -R "$SOURCE/bin" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
cd "$SCRATCH"
export WORKLOG_REPO="$SCRATCH"
git config user.email "testuser@example.com"
git config user.name "phase3-test"
git remote add origin "$UPSTREAM"
git add -A && git -c commit.gpgsign=false commit -q -m "seed: bin" --no-verify
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

LDAP="testuser"
export WORKLOG_LDAP="$LDAP"
# Strip cloned corpus so verify --all assertions see only what this test creates.
rm -rf people
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"
git add -A && git commit -q -m "seed" --no-verify && git push -q origin main

export WORKLOG_SKIP_PROVENANCE=1
mkdir -p .cache; touch .cache/provenance-verified

echo ""
echo "=== 3.1: stacking-strategy parser converts markdown → tasks JSON ==="
INPUT="$(cat <<'EOF'
# Some plan

### Stack Plan

#### PR 1: Add new schema column
Some prose.
Depends on: none

#### PR 2: Backfill old rows
Depends on: PR 1

#### PR 3: Flip read path
Depends on: PR 1, PR 2

### Out of scope
EOF
)"
OUT="$(echo "$INPUT" | "$WORKLOG_BIN/_stacking_strategy_parser.py")"
echo "$OUT"
echo "$OUT" | python3 -c '
import json, sys
tasks = json.load(sys.stdin)
assert len(tasks) == 3, f"expected 3 tasks, got {len(tasks)}"
slugs = [t["slug"] for t in tasks]
assert slugs[0].startswith("add-new-schema"), f"slug 0 = {slugs[0]}"
assert "depends_on" not in tasks[0] or tasks[0]["depends_on"] == [], "PR 1 should have no deps"
assert tasks[1]["depends_on"] == [slugs[0]], f"PR 2 deps = {tasks[1]['depends_on']}"
assert tasks[2]["depends_on"] == [slugs[0], slugs[1]], f"PR 3 deps = {tasks[2]['depends_on']}"
print("  parser OK")
'

echo ""
echo "=== 3.2: project verify --all on empty corpus is clean ==="
"$WORKLOG_BIN/project.sh" verify --all
echo ""

echo ""
echo "=== 3.3: project new + verify detects parent_slug consistency ==="
TASKS='[{"slug":"v3-a"},{"slug":"v3-b","depends_on":["v3-a"]}]'
echo "$TASKS" | "$WORKLOG_BIN/project.sh" new v3-proj --goal "verify test" --objective "two tasks"
"$WORKLOG_BIN/project.sh" verify v3-proj
echo "  ✓ clean project verifies clean"

# Break it: edit child to point at wrong parent.
sed -i.bak 's/^parent_slug: v3-proj/parent_slug: wrong-parent/' "people/$LDAP/active/v3-a.md"
rm "people/$LDAP/active/v3-a.md.bak"
set +e
"$WORKLOG_BIN/project.sh" verify v3-proj
rc=$?
set -e
[[ $rc -eq 1 ]] || { echo "FAIL: expected exit 1 (warnings), got $rc"; exit 1; }
echo "  ✓ verify reports parent_slug mismatch as warning (exit 1)"

echo ""
echo "=== 3.4: project list shows status rollup ==="
OUT="$("$WORKLOG_BIN/project.sh" list)"
echo "$OUT"
echo "$OUT" | grep -q "v3-proj" || { echo "FAIL: list missing v3-proj"; exit 1; }
echo "$OUT" | grep -qE "2 tasks" || { echo "FAIL: list missing task count"; exit 1; }
echo "  ✓ list shows project + rollup"

echo ""
echo "=== 3.5: Cursor session id env honored ==="
sid="$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_SESSION_ID -u OPENAI_SESSION_ID \
       CURSOR_SESSION_ID=cur-xyz bash -c '. "$WORKLOG_BIN/_lib.sh"; resolve_session_id')"
[[ "$sid" == "cursor:cur-xyz" ]] || { echo "FAIL: expected cursor:cur-xyz, got '$sid'"; exit 1; }
echo "  ✓ CURSOR_SESSION_ID resolves to 'cursor:<id>'"

echo ""
echo "=== 3.6: machine-UUID fallback when no session env set ==="
HOME_DIR="$SCRATCH_ROOT/home"
mkdir -p "$HOME_DIR"
sid="$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_SESSION_ID -u OPENAI_SESSION_ID -u CURSOR_SESSION_ID \
       HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
       bash -c '. "$WORKLOG_BIN/_lib.sh"; resolve_session_id')"
[[ "$sid" =~ ^machine: ]] || { echo "FAIL: expected machine:<uuid>, got '$sid'"; exit 1; }
# Second call should return the same uuid (persisted).
sid2="$(env -u CLAUDE_CODE_SESSION_ID -u CODEX_SESSION_ID -u OPENAI_SESSION_ID -u CURSOR_SESSION_ID \
        HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        bash -c '. "$WORKLOG_BIN/_lib.sh"; resolve_session_id')"
[[ "$sid" == "$sid2" ]] || { echo "FAIL: machine UUID not stable across calls"; exit 1; }
echo "  ✓ machine UUID fallback works + persists"

echo ""
echo "=== 3.7: LOCKED_BY dry-run surfaces host + started_at ==="
TASKS='[{"slug":"p3-a"},{"slug":"p3-b"}]'
echo "$TASKS" | "$WORKLOG_BIN/project.sh" new p3-proj --goal x --objective x --stale-after=1h
env -u CODEX_SESSION_ID CLAUDE_CODE_SESSION_ID=fake-a "$WORKLOG_BIN/project.sh" claim p3-a --project=p3-proj >/dev/null
out="$(env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b "$WORKLOG_BIN/project.sh" claim p3-a --project=p3-proj --dry-run 2>&1 || true)"
echo "  $out"
echo "$out" | grep -q "LOCKED_BY=claude-code:fake-a" || { echo "FAIL: missing LOCKED_BY session"; exit 1; }
echo "$out" | grep -q "host=claude-code" || { echo "FAIL: missing host= in LOCKED_BY"; exit 1; }
echo "$out" | grep -q "started=" || { echo "FAIL: missing started= in LOCKED_BY"; exit 1; }
echo "  ✓ LOCKED_BY surfaces host + started_at"

echo ""
echo "All phase-3 assertions passed."
trap - ERR
rm -rf "$SCRATCH_ROOT"
