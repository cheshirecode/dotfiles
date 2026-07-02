#!/usr/bin/env bash
set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"
SCRATCH_ROOT="$(mktemp -d -t worklog-scrape-slack-test-XXXXXX)"
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

mkdir -p people/tester/active people/tester/archive people/peer/active

cat > people/tester/active/slack-task.md <<'EOF'
---
slug: slack-task
kind: impl
status: in-progress
project: slack-project
last_updated: 2026-07-02
next_action: "Use Slack context"
pr: [123]
repos: [fixture]
---

## Context
Existing task.

## Next
- [ ] Continue
EOF

cat > people/tester/active/dup-task.md <<'EOF'
---
slug: dup-task
kind: impl
status: in-progress
project: slack-project
last_updated: 2026-07-02
next_action: "Already has Slack ref"
repos: [fixture]
external_refs:
  - platform: slack
    url: https://example.slack.com/archives/C1/p111
    note: already captured
---

## Context
Existing duplicate.
EOF

cat > people/tester/archive/old-task.md <<'EOF'
---
slug: old-task
kind: impl
status: archived
project: slack-project
last_updated: 2026-07-02
next_action: ""
repos: [fixture]
---

## Context
Archived task.
EOF

cat > people/peer/active/peer-task.md <<'EOF'
---
slug: peer-task
kind: impl
status: in-progress
project: peer-project
last_updated: 2026-07-02
next_action: "Peer owns this"
repos: [fixture]
---

## Context
Peer task.
EOF

git add people
git commit -q -m "seed scrape slack fixture" --no-verify

cat > "$SCRATCH_ROOT/slack.json" <<'JSON'
{
  "workspace": {"id": "T1", "name": "fixture"},
  "messages": [
    {
      "permalink": "https://example.slack.com/archives/C1/p100",
      "channel": "C1",
      "ts": "100.000",
      "thread_ts": "100.000",
      "surface": "public",
      "text": "slack-task PR #123 needs the updated context xoxb-secret-token",
      "summary": "Decision: use the Slack context for slack-task xoxb-secret-token"
    },
    {
      "permalink": "https://example.slack.com/archives/C1/p111",
      "channel": "C1",
      "ts": "111.000",
      "thread_ts": "111.000",
      "surface": "public",
      "text": "dup-task already captured",
      "summary": "Duplicate"
    },
    {
      "permalink": "https://example.slack.com/archives/C1/p200",
      "channel": "C1",
      "ts": "200.000",
      "thread_ts": "200.000",
      "surface": "public",
      "text": "old-task came up again",
      "summary": "Archived follow-up"
    },
    {
      "permalink": "https://example.slack.com/archives/C1/p300",
      "channel": "C1",
      "ts": "300.000",
      "thread_ts": "300.000",
      "surface": "public",
      "text": "peer-task has context",
      "summary": "Peer note"
    },
    {
      "permalink": "https://example.slack.com/archives/D1/p400",
      "channel": "D1",
      "ts": "400.000",
      "thread_ts": "400.000",
      "surface": "dm",
      "text": "slack-task private note",
      "summary": "Private note"
    }
  ]
}
JSON

out="$("$WORKLOG_BIN/scrape-slack.sh" --input "$SCRATCH_ROOT/slack.json" --format=json)"
SCRAPE_OUT="$out" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "preview"
actions = {p["source"]["permalink"]: p for p in data["proposals"]}
assert actions["https://example.slack.com/archives/C1/p100"]["action"] == "edit_candidate"
assert actions["https://example.slack.com/archives/C1/p111"]["action"] == "duplicate_ignored"
assert actions["https://example.slack.com/archives/C1/p200"]["action"] == "proposal_only"
assert actions["https://example.slack.com/archives/C1/p200"]["match"]["decision"] == "archived task is not revived"
assert actions["https://example.slack.com/archives/C1/p300"]["match"]["decision"] == "peer-owned task"
assert data["coverage"]["skipped"][0]["surface"] == "dm"
dump = json.dumps(data)
assert "xoxb-secret-token" not in dump
assert "[REDACTED]" in dump
assert len(data["checkpoint_batch"]) == 1
assert data["checkpoint_batch"][0]["slug"] == "slack-task"
PY

unavailable="$("$WORKLOG_BIN/scrape-slack.sh" --format=json)"
SCRAPE_OUT="$unavailable" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "unavailable"
assert data["writes"]["performed"] is False
PY

# --- --apply writer tests ---

apply_out="$("$WORKLOG_BIN/scrape-slack.sh" --input "$SCRATCH_ROOT/slack.json" --apply --format=json)"
SCRAPE_OUT="$apply_out" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "applied"
assert data["writes"]["performed"] is True
records = {r["slug"]: r for r in data["writes"]["records"]}
assert "slack-task" in records
assert records["slack-task"]["written"] is True
assert "external_refs" in records["slack-task"]["changes"]
assert "notes_from_slack" in records["slack-task"]["changes"]
# Only edit_candidate got written — peer-task / old-task / dup-task absent
assert "peer-task" not in records
assert "old-task" not in records
assert "dup-task" not in records
# No raw secrets in the write payload
assert "xoxb-secret-token" not in json.dumps(data)
PY

# Verify the file was actually mutated
SLACK_TASK="$SCRATCH/people/tester/active/slack-task.md"
grep -q "url: https://example.slack.com/archives/C1/p100" "$SLACK_TASK"
grep -q "## Notes from Slack" "$SLACK_TASK"
grep -q "\[REDACTED\]" "$SLACK_TASK"
! grep -q "xoxb-secret-token" "$SLACK_TASK"

# Idempotent re-apply: second run should report written=False
apply_out2="$("$WORKLOG_BIN/scrape-slack.sh" --input "$SCRATCH_ROOT/slack.json" --apply --format=json)"
SCRAPE_OUT="$apply_out2" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "applied"
assert data["writes"]["performed"] is False
records = {r["slug"]: r for r in data["writes"]["records"]}
# slack-task permalink now a duplicate → not an edit_candidate → no write record
assert "slack-task" not in records or records["slack-task"]["written"] is False
PY

# --apply without --input should refuse
refuse_rc=0
"$WORKLOG_BIN/scrape-slack.sh" --apply --format=json >"$SCRATCH_ROOT/refuse.json" 2>/dev/null || refuse_rc=$?
test "$refuse_rc" -eq 2
SCRAPE_OUT="$(cat "$SCRATCH_ROOT/refuse.json")" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "refused"
assert data["writes"]["performed"] is False
PY

echo "ok: scrape-slack preview, redaction, private skip, unavailable provider, --apply writer, idempotent re-apply, --apply refuse without input"
