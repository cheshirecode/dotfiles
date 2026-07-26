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
mkdir -p people/tester/active people/tester/archive

cat > people/tester/active/good-task.md <<'EOF'
---
slug: good-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-12
next_action: Keep going
repos: [sample]
---

## Context
Good task body.

## Next
Keep going.
EOF

cat > people/tester/active/bad-task.md <<'EOF'
---
slug: bad-task
kind: impl
status: done
project: sample
last_updated: 2026-06-12
next_action: Fix status
repos: [sample]
---

## Context
Bad task body.

## Next
Fix status.
EOF

"$WORKLOG_BIN/lint.sh" --help | grep -q -- '--file=PATH'

good_json="$("$WORKLOG_BIN/lint.sh" --file=people/tester/active/good-task.md --format=json)"
printf '%s' "$good_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["total_files"] == 1, d
assert d["total_errors"] == 0, d
assert d["files_with_issues"] == 0, d
'

bad_json="$("$WORKLOG_BIN/lint.sh" --file=people/tester/active/bad-task.md --format=json 2>/dev/null || true)"
printf '%s' "$bad_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["total_files"] == 1, d
assert d["total_errors"] == 1, d
assert len(d["issues"]) == 1, d
assert d["issues"][0]["file"] == "people/tester/active/bad-task.md", d
assert "status" in d["issues"][0]["errors"][0], d
'

if "$WORKLOG_BIN/lint.sh" --file=people/tester/active/missing-task.md >/tmp/worklog-lint-missing.out 2>&1; then
  echo "FAIL: missing --file path should fail"
  exit 1
fi
grep -q 'is not a tracked task file' /tmp/worklog-lint-missing.out

mkdir -p people/tester/archived
cat > people/tester/archived/good-task.md <<'EOF'
---
slug: good-task
kind: impl
status: archived
project: sample
last_updated: 2026-06-12
next_action: —
repos: [sample]
---

## Context
Invisible duplicate in an unsupported state directory.

## Next
None.
EOF

# Transcripts are supported auxiliary Markdown and intentionally share task slugs.
mkdir -p people/tester/transcripts
cat > people/tester/transcripts/good-task.md <<'EOF'
# Transcript

Session evidence for good-task.
EOF

layout_json="$("$WORKLOG_BIN/lint.sh" --format=json 2>/dev/null || true)"
printf '%s' "$layout_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
errors = [
    error
    for issue in d["issues"]
    for error in issue["errors"]
]
assert any("unknown task state directory" in error and "archived" in error for error in errors), errors
assert any("duplicate slug" in error and "good-task" in error for error in errors), errors
assert not any("transcripts" in error for error in errors), errors
'

# File-scoped lint remains scoped to the requested canonical task.
good_json="$("$WORKLOG_BIN/lint.sh" --file=people/tester/active/good-task.md --format=json)"
printf '%s' "$good_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["total_files"] == 1, d
assert d["total_errors"] == 0, d
'

echo "ok: lint --file scope and vault layout"
