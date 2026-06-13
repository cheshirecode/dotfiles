#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

UPSTREAM="$TMP/upstream.git"
WORK="$TMP/work"
git init -q --bare "$UPSTREAM"
git init -q "$WORK"
cd "$WORK"
git config user.email tester@example.com
git config user.name Tester
git remote add origin "$UPSTREAM"

mkdir -p people/tester/active
cat > people/tester/active/batch-task.md <<'EOF'
---
slug: batch-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-01
next_action: Keep going
repos: [sample]
pr: [1]
---

## Context
Batch task body.

## Next
Keep going.
EOF

git add people/tester/active/batch-task.md
git commit -q -m "batch-task: create" -m "Worklog-Slug: batch-task"
git branch -M main
git push -q -u origin main

printf '[{"slug":"batch-task","pr":2,"next":"Review PR 2"}]\n' \
  | WORKLOG_LDAP=tester WORKLOG_NO_HOOK=1 "$WORKLOG_BIN/checkpoint-batch.sh" >/tmp/worklog-batch-pr-merge.out

grep -q "checkpoint-batch: pushed 1 tasks" /tmp/worklog-batch-pr-merge.out
grep -q '^pr: \[1, 2\]$' people/tester/active/batch-task.md
git log -1 --format=%B | grep -q 'Worklog-Slug: batch-task'

echo "ok: checkpoint-batch pr merge"
