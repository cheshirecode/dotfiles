#!/usr/bin/env bash
# roster-health must compare *which* tasks the kernel cache holds, not how many.
#
# The failure this pins: archive one task and create another inside the 1h
# freshness window and the counts still match, so the count-only check reported
# `fresh` and served the cached roster — listing the archived task and omitting
# the new one, with no warning. Silent wrong answer, the repo's canonical
# defect shape.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/people/tester/active" "$TMP/people/tester/archive"
git -C "$TMP" init -q
git -C "$TMP" config user.email tester@example.com
git -C "$TMP" config user.name Tester

write_task() {
  cat > "$TMP/people/tester/active/$1.md" <<EOF
---
slug: $1
kind: investigation
status: in-progress
project: sample
last_updated: 2026-07-2$2
next_action: Work on $1
repos: [sample]
---

## Context
Roster drift fixture.

## Next
- [ ] Work on $1
EOF
}

write_task task-a 5
write_task task-b 6

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/compact-kernels.sh" >/dev/null

# Same-count drift: one task leaves active, one arrives. 2 before, 2 after.
mv "$TMP/people/tester/active/task-b.md" "$TMP/people/tester/archive/task-b.md"
write_task task-c 7

preamble="$(
  WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
    "$WORKLOG_BIN/preamble.sh" --minimal
)"

if grep -q 'roster-health: fresh' <<< "$preamble"; then
  echo "FAIL: cache holding an archived task and missing a new one reported fresh"
  printf '%s\n' "$preamble" | grep 'roster-health'
  exit 1
fi
if ! grep -q 'roster-health: mismatch kernels=2 active_namespace=2 active_total=2 missing=1 extra=1' <<< "$preamble"; then
  echo "FAIL: expected a mismatch line naming the missing and extra slugs"
  printf '%s\n' "$preamble" | grep 'roster-health'
  exit 1
fi
# Degraded health must be loud, not a `#` comment a reader scrolls past.
if grep -Eq '^#[[:space:]]*roster-health: mismatch' <<< "$preamble"; then
  echo "FAIL: degraded roster-health is still commented out"
  exit 1
fi
if ! grep -q $'task-c\tin-progress\tWork on task-c' <<< "$preamble"; then
  echo "FAIL: roster omitted the task created after the cache was built"
  exit 1
fi
if grep -q $'task-b\t' <<< "$preamble"; then
  echo "FAIL: roster still lists the archived task from the stale cache"
  exit 1
fi

# Equal sets must stay quiet: rebuilding the cache clears the warning.
WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/compact-kernels.sh" >/dev/null
fresh_preamble="$(
  WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
    "$WORKLOG_BIN/preamble.sh" --minimal
)"
grep -q '# roster-health: fresh kernels=2 active_namespace=2 active_total=2' <<< "$fresh_preamble"
grep -q $'task-c\tin-progress\tWork on task-c' <<< "$fresh_preamble"

echo "ok: roster-health detects same-count cache drift and stays quiet when the sets match"
