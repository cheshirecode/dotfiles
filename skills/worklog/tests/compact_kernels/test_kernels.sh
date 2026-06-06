#!/usr/bin/env bash
# End-to-end test for bin/compact-kernels.sh.
#
# Asserts the resume-kernel cache that PreCompact / SessionEnd hooks dump
# is well-formed and useful for the next session's preamble (skill SKILL.md
# step 0 reads this file when fresh).
#
# Runs against a scratch clone with synthetic active tasks under
# people/$LDAP/active/, so we can exercise:
#   1. Header — generated timestamp + "Stale after:" line present
#   2. Per-task — one `### <slug>` section per active task
#   3. Body    — each section contains the slug's frontmatter (kernel non-empty)
#   4. Empty   — no active tasks → "_(no active tasks)_" placeholder, no error
#   5. Idempotent — second run produces the same shape (file rewritten, not appended)
#
# Usage:
#   tests/compact_kernels/test_kernels.sh
#   SOURCE=/path/to/repo tests/compact_kernels/test_kernels.sh

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SOURCE="${SOURCE:-$(pwd)}"

SCRATCH_ROOT="$(mktemp -d -t compact-kernels-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
# Isolate the LDAP cache so the test doesn't poison the real user's cache
# in $TMPDIR/worklog-ldap-$USER (resolve_ldap caches there for 24h).
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'echo "scratch: $SCRATCH_ROOT (left for inspection)"' ERR

echo "=== Test setup ==="
echo "Source: $SOURCE"
echo "Scratch: $SCRATCH"
git clone -q "$SOURCE" "$SCRATCH"
cd "$SCRATCH"
git config user.email "test@example.com"
git config user.name "compact-kernels-test"

# Force a deterministic LDAP via the (isolated) cache resolve_ldap reads.
LDAP="testuser"
printf '%s' "$LDAP" > "$TMPDIR/worklog-ldap-${USER}"
ACTIVE="people/$LDAP/active"
mkdir -p "$ACTIVE" "people/$LDAP/archive"
touch "people/$LDAP/archive/.gitkeep"

# Synthetic active tasks (minimal frontmatter — enough for context.sh --for=compact).
write_task() {
  local slug="$1" status="$2" next="$3"
  cat > "$ACTIVE/$slug.md" <<EOF
---
slug: $slug
status: $status
kind: feature
project: test-project
last_updated: $(date +%Y-%m-%d)
next_action: "$next"
---

## Context

Synthetic test task for compact-kernels e2e.

## Next

- [ ] $next
EOF
}

write_task task-alpha in-progress "implement alpha"
write_task task-beta blocked     "Waiting on alpha"
write_task task-gamma in-review  "address review feedback"

git add people/
git -c commit.gpgsign=false commit -q -m "test: seed 3 active tasks" --no-verify

echo ""
echo "=== Run 1 — three active tasks ==="
"$WORKLOG_BIN/compact-kernels.sh"
OUT=".cache/compact-kernels.md"

# Assertion 1: file exists and is non-empty.
[[ -s "$OUT" ]] || { echo "FAIL: $OUT missing or empty"; exit 1; }
echo "  ✓ $OUT exists ($(wc -l <"$OUT" | tr -d ' ') lines)"

# Assertion 2: header lines.
grep -q "^# Compact kernels — generated" "$OUT" \
  || { echo "FAIL: missing 'generated' header"; exit 1; }
grep -q "^# Stale after:" "$OUT" \
  || { echo "FAIL: missing 'Stale after' header"; exit 1; }
echo "  ✓ headers present (generated + stale-after)"

# Assertion 3: one section per task.
for slug in task-alpha task-beta task-gamma; do
  grep -q "^### $slug\$" "$OUT" \
    || { echo "FAIL: missing section ### $slug"; exit 1; }
done
SECTION_COUNT=$(grep -c '^### ' "$OUT")
[[ "$SECTION_COUNT" -eq 3 ]] \
  || { echo "FAIL: expected 3 sections, got $SECTION_COUNT"; exit 1; }
echo "  ✓ one section per active task (3/3)"

# Assertion 3b: JSON sibling exists, parses, has correct record count + shape.
JSON=".cache/compact-kernels.json"
[[ -s "$JSON" ]] || { echo "FAIL: $JSON missing or empty"; exit 1; }
python3 - "$JSON" <<'PY' || { echo "FAIL: JSON shape check"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d) == 3, f"expected 3 records, got {len(d)}"
slugs = {r["slug"] for r in d}
assert slugs == {"task-alpha", "task-beta", "task-gamma"}, f"slug mismatch: {slugs}"
required = {"slug", "status", "last_updated", "last_sha", "next_action", "open_items"}
for r in d:
  missing = required - r.keys()
  assert not missing, f"record {r['slug']} missing keys: {missing}"
PY
echo "  ✓ JSON sibling has 3 records with required keys"

# Assertion 4: each section's body is non-trivial.
# context.sh --for=compact emits frontmatter-derived lines; assert the
# next_action / status from each task survives into the kernel.
grep -q "implement alpha" "$OUT" \
  || { echo "FAIL: task-alpha next_action missing from kernel body"; exit 1; }
grep -q "Waiting on alpha" "$OUT" \
  || { echo "FAIL: task-beta next_action missing from kernel body"; exit 1; }
grep -q "address review feedback" "$OUT" \
  || { echo "FAIL: task-gamma next_action missing from kernel body"; exit 1; }
echo "  ✓ each kernel body contains its task's next_action"

# Assertion 5: no "kernel generation failed" sentinels.
if grep -q "kernel generation failed" "$OUT"; then
  echo "FAIL: at least one kernel failed to generate"
  grep -n "kernel generation failed" "$OUT"
  exit 1
fi
echo "  ✓ no kernel generation failures"

echo ""
echo "=== Run 2 — idempotent rewrite ==="
PREV_HASH=$(sha256sum "$OUT" | awk '{print $1}')
sleep 1  # ensure timestamp changes if regenerated
"$WORKLOG_BIN/compact-kernels.sh"
NEW_HASH=$(sha256sum "$OUT" | awk '{print $1}')
# Hashes will differ because of timestamp lines, but section count must match.
NEW_SECTION_COUNT=$(grep -c '^### ' "$OUT")
[[ "$NEW_SECTION_COUNT" -eq 3 ]] \
  || { echo "FAIL: idempotent run produced $NEW_SECTION_COUNT sections (expected 3)"; exit 1; }
echo "  ✓ second run still produces 3 sections (file rewritten, not appended)"

echo ""
echo "=== Run 3 — empty active dir ==="
rm -f "$ACTIVE"/*.md
"$WORKLOG_BIN/compact-kernels.sh"
grep -q "_(no active tasks)_" "$OUT" \
  || { echo "FAIL: empty-dir placeholder missing"; cat "$OUT"; exit 1; }
[[ "$(grep -c '^### ' "$OUT")" -eq 0 ]] \
  || { echo "FAIL: sections present despite empty active dir"; exit 1; }
echo "  ✓ empty active dir → '_(no active tasks)_' placeholder, no sections"

echo ""
echo "All assertions passed."
trap - ERR
rm -rf "$SCRATCH_ROOT"
