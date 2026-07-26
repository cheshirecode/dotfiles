#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/people/tester/active" "$TMP/people/tester/archive"
git -C "$TMP" init -q
git -C "$TMP" config user.email tester@example.com
git -C "$TMP" config user.name Tester

cat > "$TMP/people/tester/active/cache-task.md" <<'EOF'
---
slug: cache-task
kind: investigation
status: draft
project: sample
last_updated: 2026-07-25
next_action: Read the original task state
repos: [sample]
---

## Context
Derived-view invalidation fixture.

## Next
- [ ] Read the original task state
EOF

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/search.sh" --list --status=draft \
  | grep -Eq '^active  +draft  +cache-task$'
[[ -s "$TMP/.cache/index.jsonl" ]]

sleep 1
python3 - "$TMP/people/tester/active/cache-task.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("status: draft", "status: in-progress")
text = text.replace(
    "Read the original task state",
    "Use the updated raw task state",
)
path.write_text(text)
PY

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/search.sh" --list --status=in-progress \
  | grep -Eq '^active  +in-progress  +cache-task$'
if WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/search.sh" --list --status=draft 2>/dev/null | grep -q 'cache-task'; then
  echo "FAIL: stale index returned the old task status"
  exit 1
fi

WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
  "$WORKLOG_BIN/compact-kernels.sh" >/dev/null
touch -t 202001010000 \
  "$TMP/.cache/compact-kernels.md" \
  "$TMP/.cache/compact-kernels.json"

preamble="$(
  WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
    "$WORKLOG_BIN/preamble.sh" --minimal
)"
grep -q 'roster-health: stale' <<< "$preamble"
if grep -q 'Use the updated raw task state' <<< "$preamble"; then
  echo "FAIL: stale kernel content leaked into the preamble roster"
  exit 1
fi

context="$(
  WORKLOG_REPO="$TMP" WORKLOG_LDAP=tester \
    "$WORKLOG_BIN/context.sh" cache-task
)"
grep -q 'Use the updated raw task state' <<< "$context"

echo "ok: stale index rebuilds and stale kernels fall through to raw context"
