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
before_kernel_mtime="$(stat -f %m "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -c %Y "$TMP/.cache/compact-kernels.json")"
before_pull_mtime="$(stat -f %m "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -c %Y "$TMP/.cache/preamble-pull-stamp")"

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/preamble.sh" --minimal >/dev/null

after_status="$(git -C "$TMP" status --porcelain)"
after_kernel_mtime="$(stat -f %m "$TMP/.cache/compact-kernels.json" 2>/dev/null || stat -c %Y "$TMP/.cache/compact-kernels.json")"
after_pull_mtime="$(stat -f %m "$TMP/.cache/preamble-pull-stamp" 2>/dev/null || stat -c %Y "$TMP/.cache/preamble-pull-stamp")"

[[ "$after_status" == "$before_status" ]]
[[ "$after_kernel_mtime" == "$before_kernel_mtime" ]]
[[ "$after_pull_mtime" == "$before_pull_mtime" ]]

echo "ok: default/light init routes to non-mutating minimal preamble"
