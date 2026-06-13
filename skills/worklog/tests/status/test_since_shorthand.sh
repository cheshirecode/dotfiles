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
export GIT_AUTHOR_NAME=Tester
export GIT_AUTHOR_EMAIL=tester@example.com
export GIT_COMMITTER_NAME=Tester
export GIT_COMMITTER_EMAIL=tester@example.com
mkdir -p people/tester/active

cat > people/tester/active/fresh-task.md <<'EOF'
---
slug: fresh-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-12
next_action: Keep going
repos: [sample]
---

## Context
Fresh task body.

## Next
Keep going.
EOF

git add people/tester/active/fresh-task.md
git commit -q -m "fresh-task: create" -m "next: Keep going" -m "Worklog-Slug: fresh-task"

json="$(WORKLOG_LDAP=tester "$WORKLOG_BIN/status.sh" --since=30d --format=json)"
printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["since"] == "30.days.ago", d
items = d["projects"]["sample"]["in-progress"]
assert items[0]["slug"] == "fresh-task", d
'

mkdir -p people/oss/active
cat > people/oss/active/oss-task.md <<'EOF'
---
slug: oss-task
kind: impl
status: in-progress
project: sample
last_updated: 2026-06-12
next_action: Keep going
repos: [sample]
---

## Context
OSS namespace task body.

## Next
Keep going.
EOF

git add people/oss/active/oss-task.md
git commit -q -m "oss-task: create" -m "next: Keep going" -m "Worklog-Slug: oss-task"

json="$(WORKLOG_LDAP=oss "$WORKLOG_BIN/status.sh" --since=30d --format=json)"
printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["author"] == "tester", d
items = d["projects"]["sample"]["in-progress"]
assert any(i["slug"] == "oss-task" for i in items), d
'

echo "ok: status --since shorthand"
