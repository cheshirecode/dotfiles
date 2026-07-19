#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from the developer's live WORKLOG_REPO (lint.sh resolves via env).
unset WORKLOG_REPO WORKLOG_LDAP || true
export WORKLOG_REPO="$TMP"

cd "$TMP"
git init -q
git config user.email tester@example.com
git config user.name Tester
mkdir -p people/tester/active

cat > people/tester/active/file-url-task.md <<'EOF'
---
slug: file-url-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-07-19
next_action: Remove file url
repos: [sample]
external_refs:
  - platform: notes
    url: file:///tmp/secret-notes.md
    note: off-repo
---

## Context
Should fail lint.

## Next
Fix refs.
EOF

cat > people/tester/active/canvas-task.md <<'EOF'
---
slug: canvas-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-07-19
next_action: Remove canvas
repos: [sample]
external_refs:
  - platform: cursor-canvas
    url: /Users/x/.cursor/projects/foo/canvases/bar.canvas.tsx
    note: canvas
---

## Context
Should fail lint.

## Next
Fix refs.
EOF

file_json="$("$WORKLOG_BIN/lint.sh" --file=people/tester/active/file-url-task.md --format=json 2>/dev/null || true)"
printf '%s' "$file_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["total_errors"] >= 1, d
assert any("file://" in e for e in d["issues"][0]["errors"]), d
'

canvas_json="$("$WORKLOG_BIN/lint.sh" --file=people/tester/active/canvas-task.md --format=json 2>/dev/null || true)"
printf '%s' "$canvas_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["total_errors"] >= 1, d
assert any("canvas" in e.lower() for e in d["issues"][0]["errors"]), d
'

echo "ok: lint bans file:// and cursor canvas external_refs"
