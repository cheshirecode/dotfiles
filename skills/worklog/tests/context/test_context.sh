#!/usr/bin/env bash
set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"
SCRATCH_ROOT="$(mktemp -d -t worklog-context-test-XXXXXX)"
SCRATCH="$SCRATCH_ROOT/repo"
export TMPDIR="$SCRATCH_ROOT/tmp"
mkdir -p "$TMPDIR"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

git init -q "$SCRATCH"
cd "$SCRATCH"
git config user.email "tester@example.com"
git config user.name "Tester"
export WORKLOG_REPO="$SCRATCH"
export WORKLOG_LDAP="tester"

mkdir -p people/tester/active people/peer/active

cat > people/tester/active/current-next.md <<'EOF'
---
slug: current-next
kind: impl
status: in-progress
project: context-test
last_updated: 2026-06-29
next_action: "Use only the current Next section"
repos: [context-test]
---

## Context

This task has a historical checklist that should not hydrate the tracker.

## Next

- [ ] Current item one
- [ ] Current item two

## Notes from older session

## Next

- [ ] Stale item from old notes
EOF

cat > people/peer/active/peer-only.md <<'EOF'
---
slug: peer-only
kind: impl
status: in-progress
project: context-test
last_updated: 2026-06-29
next_action: "Read-only peer lookup"
repos: [context-test]
---

## Context

Peer-owned task used to prove unique read-only slug lookup.

## Next

- [ ] Peer item
EOF

git add people/
git commit -q -m "context-test: seed tasks" --no-verify

json="$(WORKLOG_LDAP=tester "$WORKLOG_BIN/context.sh" current-next --format=json)"
CONTEXT_JSON="$json" python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["CONTEXT_JSON"])
items = [item["text"] for item in data["work_items"] if item["status"] == "open"]
assert items == ["Current item one", "Current item two"], items
PY

out="$(WORKLOG_LDAP=tester "$WORKLOG_BIN/context.sh" peer-only --for=compact)"
printf '%s\n' "$out" | grep -q '^slug: peer-only$'
printf '%s\n' "$out" | grep -q 'Read-only peer lookup'

echo "ok: context current-next hydration and unique peer lookup"
