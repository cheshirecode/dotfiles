#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
SKILL_ROOT="$ROOT/SKILL.md"
INIT_MODE="$ROOT/modes/init.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

grep -Fq 'default / `--light` → `--minimal`' "$SKILL_ROOT"
grep -Fq 'explicit `--full` → `--full`' "$SKILL_ROOT"
grep -Fq 'Default and `--light` use `preamble.sh --minimal`' "$INIT_MODE"
grep -Fq 'Do not hydrate `TaskCreate` or `update_plan` before the user selects a task.' "$INIT_MODE"
if grep -Fq 'for any active task with ≥3 unchecked items' "$INIT_MODE"; then
  echo "FAIL: init still hydrates every multi-step active task"
  exit 1
fi

mkdir -p "$TMP/people/tester/active" "$TMP/people/tester/archive" "$TMP/.cache"
git -C "$TMP" init -q
git -C "$TMP" config user.email tester@example.com
git -C "$TMP" config user.name Tester

cat > "$TMP/people/tester/active/light-init.md" <<'EOF'
---
slug: light-init
kind: investigation
status: in-progress
project: sample
last_updated: 2026-07-25
next_action: Verify light init
repos: [sample]
---

## Context
Dirty-clone light-init fixture.

## Next
Verify light init.
EOF

printf '[]\n' > "$TMP/.cache/compact-kernels.json"
printf 'keep\n' > "$TMP/.cache/preamble-pull-stamp"
git -C "$TMP" add people .cache
git -C "$TMP" commit -qm "fixture"
printf '\ndirty\n' >> "$TMP/people/tester/active/light-init.md"

before_status="$(git -C "$TMP" status --porcelain)"
before_kernel_mtime="$(stat -c %Y "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -f %m "$TMP/.cache/compact-kernels.json")"
before_pull_mtime="$(stat -c %Y "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -f %m "$TMP/.cache/preamble-pull-stamp")"

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/preamble.sh" --minimal >/dev/null

after_status="$(git -C "$TMP" status --porcelain)"
after_kernel_mtime="$(stat -c %Y "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -f %m "$TMP/.cache/compact-kernels.json")"
after_pull_mtime="$(stat -c %Y "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -f %m "$TMP/.cache/preamble-pull-stamp")"

[[ "$after_status" == "$before_status" ]]
[[ "$after_kernel_mtime" == "$before_kernel_mtime" ]]
[[ "$after_pull_mtime" == "$before_pull_mtime" ]]

echo "ok: --minimal accepted (non-mutating)"

# Restore fixture for --light test
git -C "$TMP" checkout -- .
printf '\ndirty\n' >> "$TMP/people/tester/active/light-init.md"
before_status="$(git -C "$TMP" status --porcelain)"
before_kernel_mtime="$(stat -c %Y "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -f %m "$TMP/.cache/compact-kernels.json")"
before_pull_mtime="$(stat -c %Y "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -f %m "$TMP/.cache/preamble-pull-stamp")"

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/preamble.sh" --light >/dev/null

after_status="$(git -C "$TMP" status --porcelain)"
after_kernel_mtime="$(stat -c %Y "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -f %m "$TMP/.cache/compact-kernels.json")"
after_pull_mtime="$(stat -c %Y "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -f %m "$TMP/.cache/preamble-pull-stamp")"

[[ "$after_status" == "$before_status" ]]
[[ "$after_kernel_mtime" == "$before_kernel_mtime" ]]
[[ "$after_pull_mtime" == "$before_pull_mtime" ]]

echo "ok: --light accepted and behaves identically to --minimal"

# Adversarial: unknown flags must be rejected.
if "$WORKLOG_BIN/preamble.sh" --bogus >/dev/null 2>&1; then
  echo "FAIL: --bogus should have been rejected"
  exit 1
fi
echo "ok: --bogus rejected (exit != 0)"
