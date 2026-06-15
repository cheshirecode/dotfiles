#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email tester@example.com
git config user.name Tester
mkdir -p people/tester/active projects

cat > .worklog-boundary.json <<'EOF'
{
  "schema": "worklog.boundary.v1",
  "label": "test tracker",
  "deny": [
    {"pattern": "foreign-system", "note": "belongs elsewhere"}
  ]
}
EOF

cat > people/tester/active/bad-task.md <<'EOF'
---
slug: bad-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-15
next_action: Fix boundary drift
---

## Context
This accidentally mentions foreign-system.
EOF

if WORKLOG_REPO="$TMP" "$WORKLOG_BIN/boundary-lint.sh" >/tmp/worklog-boundary.out 2>&1; then
  echo "FAIL: boundary-lint should reject the fixture"
  exit 1
fi
grep -q 'bad-task.md:11' /tmp/worklog-boundary.out
grep -q 'belongs elsewhere' /tmp/worklog-boundary.out

python3 - "$WORKLOG_BIN" "$TMP" <<'PY'
import json
import os
import subprocess
import sys

bin_dir, repo = sys.argv[1:]
env = os.environ.copy()
env["WORKLOG_REPO"] = repo
result = subprocess.run(
    [f"{bin_dir}/boundary-lint.sh", "--format=json"],
    env=env,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=False,
)
data = json.loads(result.stdout)
assert result.returncode == 1, result
assert data["label"] == "test tracker", data
assert data["total"] == 1, data
assert data["issues"][0]["file"] == "people/tester/active/bad-task.md", data
PY

perl -0pi -e 's/foreign-system/local-system/g' people/tester/active/bad-task.md
WORKLOG_REPO="$TMP" "$WORKLOG_BIN/boundary-lint.sh" | grep -q 'clean'

echo "ok: boundary lint"
