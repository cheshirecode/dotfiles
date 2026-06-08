#!/usr/bin/env bash
# End-to-end test for `bin/project.sh` phase 2 (advisory mutex).
#
# Acceptance (from worklog-project-mode.md § Phase 2):
#   Two shells with distinct fake session IDs both run `project claim next`
#   against a 2-task project. Each holds a different task (no double-claim).
#   With mutex.stale_after=10s, "kill" shell A (clear its heartbeat env);
#   wait >10s; run `project reap`. A's claim is cleared; B's is not.
#
# Speed-up: we use --stale-after=10s instead of 1m so the test stays fast.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t project-phase2-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
UPSTREAM="$SCRATCH_ROOT/upstream.git"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Test setup ==="
git init -q --bare "$UPSTREAM"
# Fresh scratch data repo (see test_phase1.sh for why we init rather than clone
# $SOURCE, and why WORKLOG_REPO must be pinned to the scratch).
git init -q "$SCRATCH"
cp -R "$SOURCE/bin" "$SCRATCH/bin"
rm -rf "$SCRATCH/bin/__pycache__"
cd "$SCRATCH"
export WORKLOG_REPO="$SCRATCH"
git config user.email "testuser@example.com"
git config user.name "project-phase2-test"
git remote add origin "$UPSTREAM"
git add -A && git -c commit.gpgsign=false commit -q -m "seed: bin" --no-verify
git push -q origin HEAD:main
git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true

LDAP="testuser"
export WORKLOG_LDAP="$LDAP"
# Strip the cloned corpus so reap-walks (which iterate every active/*.md)
# don't pick up production stale claims and don't slow down enough for the
# 10s stale window to race against per-file subprocess overhead. Same fix
# shipped to test_phase3.sh on 2026-05-13.
rm -rf people
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"
git add -A
git commit -q -m "test: seed ldap dirs" --no-verify
git push -q origin main

export WORKLOG_SKIP_PROVENANCE=1
mkdir -p .cache; touch .cache/provenance-verified

echo ""
echo "=== 2.1: project new (2-task project, stale_after=10s) ==="
TASKS='[{"slug":"p2-a"},{"slug":"p2-b"}]'
echo "$TASKS" | "$WORKLOG_BIN/project.sh" new p2-proj \
  --goal "phase 2 test" \
  --objective "two parallel tasks" \
  --stale-after=10s
grep -q '^kind: project$' "people/$LDAP/active/p2-proj.md" || { echo "FAIL: missing kind: project"; exit 1; }
grep -q 'stale_after: 10s' "people/$LDAP/active/p2-proj.md" || { echo "FAIL: stale_after not 10s"; exit 1; }
echo "  ✓ project created with 10s stale-after"

echo ""
echo "=== 2.2: two distinct sessions claim 'next' — each gets a different task ==="
out_a="$(env -u CODEX_SESSION_ID CLAUDE_CODE_SESSION_ID=fake-a "$WORKLOG_BIN/project.sh" claim next p2-proj 2>&1)"
echo "$out_a"
out_b="$(env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b "$WORKLOG_BIN/project.sh" claim next p2-proj 2>&1)"
echo "$out_b"

# Read claims back from disk.
claim_a="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-a.md)"
claim_b="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-b.md)"
sid_a="$(echo "$claim_a" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"
sid_b="$(echo "$claim_b" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"
echo "  p2-a held by: $sid_a"
echo "  p2-b held by: $sid_b"
[[ -n "$sid_a" && -n "$sid_b" ]] || { echo "FAIL: at least one task has no claim"; exit 1; }
[[ "$sid_a" != "$sid_b" ]] || { echo "FAIL: both tasks held by same session"; exit 1; }
echo "  ✓ two tasks held by two distinct sessions"

echo ""
echo "=== 2.3: 'claim next' when nothing eligible — exit non-zero ==="
if env -u CODEX_SESSION_ID CLAUDE_CODE_SESSION_ID=fake-c \
   "$WORKLOG_BIN/project.sh" claim next p2-proj 2>/dev/null; then
  echo "FAIL: expected non-zero when all eligible tasks are locked"
  exit 1
fi
echo "  ✓ third session finds nothing eligible"

echo ""
echo "=== 2.4: --dry-run reports LOCKED_BY without writing ==="
out="$(env -u CODEX_SESSION_ID CLAUDE_CODE_SESSION_ID=fake-c \
       "$WORKLOG_BIN/project.sh" claim p2-a --dry-run 2>&1 || true)"
echo "  $out"
echo "$out" | grep -q "LOCKED_BY" || { echo "FAIL: dry-run did not report LOCKED_BY"; exit 1; }
echo "  ✓ --dry-run reports LOCKED_BY (no write)"

echo ""
echo "=== 2.5: wait >10s, reap — A's claim cleared (B's still fresh) ==="
# Derive which task fake-b holds.
b_task=""
for t in p2-a p2-b; do
  sid="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/$t.md | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"
  [[ "$sid" == *fake-b* ]] && b_task="$t"
done
[[ -n "$b_task" ]] || { echo "FAIL: could not find B's task"; exit 1; }
sleep 12
# Re-tick B's heartbeat to refresh it post-sleep.
env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b \
  python3 "$WORKLOG_BIN/_claim.py" tick "people/$LDAP/active/$b_task.md" --session=codex:fake-b
"$WORKLOG_BIN/project.sh" reap

# Check: A's claim cleared, B's intact.
after_a="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-a.md)"
after_b="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-b.md)"
ha="$(echo "$after_a" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("has_claim"))')"
hb="$(echo "$after_b" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("has_claim"))')"
echo "  p2-a has_claim=$ha; p2-b has_claim=$hb"
# A might be either p2-a or p2-b depending on which it claimed; the cleared one
# was the stale-A claim (fake-a), the surviving one is fake-b.
surviving_sid=""
for t in p2-a p2-b; do
  sid="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/$t.md | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id") or "")')"
  [[ -n "$sid" ]] && surviving_sid="$sid"
done
[[ "$surviving_sid" == codex:fake-b ]] || { echo "FAIL: expected codex:fake-b to survive reap, got '$surviving_sid'"; exit 1; }
echo "  ✓ A's stale claim cleared; B's fresh claim survived"

echo ""
echo "=== 2.6: release clears my own claim ==="
env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b \
  "$WORKLOG_BIN/project.sh" release "$b_task"
after="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/$b_task.md | python3 -c 'import json,sys;print(json.load(sys.stdin).get("has_claim"))')"
[[ "$after" == "False" ]] || { echo "FAIL: release did not clear claim ($after)"; exit 1; }
echo "  ✓ release cleared own claim"

echo ""
echo "=== 2.7: heartbeat tick on checkpoint.sh — frontmatter heartbeat_at advances ==="
# Re-claim, capture timestamp, sleep 2s, checkpoint, verify heartbeat advanced.
env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b \
  "$WORKLOG_BIN/project.sh" claim p2-a --project=p2-proj >/dev/null
hb1="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-a.md | python3 -c 'import json,sys;print(json.load(sys.stdin).get("heartbeat_at"))')"
# Bump next_action to force a semantic-diff commit, then checkpoint.
sleep 2
env -u CLAUDE_CODE_SESSION_ID CODEX_SESSION_ID=fake-b \
  "$WORKLOG_BIN/checkpoint.sh" p2-a --next="new step at $(date +%H:%M:%S)" >/dev/null 2>&1 || true
hb2="$(python3 "$WORKLOG_BIN/_claim.py" read people/$LDAP/active/p2-a.md | python3 -c 'import json,sys;print(json.load(sys.stdin).get("heartbeat_at"))')"
echo "  before: $hb1"
echo "  after:  $hb2"
[[ "$hb1" != "$hb2" ]] || { echo "FAIL: heartbeat_at did not advance after checkpoint"; exit 1; }
echo "  ✓ heartbeat advances on owner's checkpoint"

echo ""
echo "All phase-2 assertions passed."
trap - ERR
rm -rf "$SCRATCH_ROOT"
