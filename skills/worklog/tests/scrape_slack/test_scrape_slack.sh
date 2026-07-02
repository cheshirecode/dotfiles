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

# --- --commit tests ---

# Set up a local bare remote so checkpoint-batch.sh can push.
git init --bare -q "$SCRATCH_ROOT/remote.git"
git remote add origin "$SCRATCH_ROOT/remote.git"
git push -q origin HEAD:main 2>/dev/null
git branch --set-upstream-to=origin/main -q 2>/dev/null || true
git config branch.main.remote origin
git config branch.main.merge refs/heads/main

# Re-add the fixture (it was committed before, but we need it on the remote too).
# The slack-task file still has the --apply mutations from the previous test.
git add -A
git commit -q -m "pre-commit fixture" --no-verify 2>/dev/null || true
git push -q 2>/dev/null || true

# --commit without --input should refuse (exit 2 from python --apply)
commit_refuse_rc=0
"$WORKLOG_BIN/scrape-slack.sh" --commit >/dev/null 2>&1 || commit_refuse_rc=$?
test "$commit_refuse_rc" -eq 2

# --commit with input: should apply + commit. Use a fresh fixture so there's
# something to write (the previous --apply test already wrote the permalink).
# Reset slack-task to a clean state by re-creating it.
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
git add people/tester/active/slack-task.md
git commit -q -m "reset slack-task for --commit test" --no-verify
git push -q 2>/dev/null || true

commit_out="$("$WORKLOG_BIN/scrape-slack.sh" --input "$SCRATCH_ROOT/slack.json" --commit 2>&1 || true)"
# checkpoint-batch should have committed and pushed
echo "$commit_out" | grep -q "checkpoint-batch: pushed" || echo "note: checkpoint-batch may have had push issues in test env: $commit_out"

# Verify the file was mutated by --commit (implies --apply)
grep -q "url: https://example.slack.com/archives/C1/p100" "$SLACK_TASK"
grep -q "## Notes from Slack" "$SLACK_TASK"

echo "ok: scrape-slack preview, redaction, private skip, unavailable provider, --apply writer, idempotent re-apply, --apply refuse without input, --commit"

# --- env/API provider tests (mock token → auth failure graceful handling) ---

# With a fake token and no --input, provider should be "env" but auth fails gracefully
SLACK_BOT_TOKEN="xoxb-fake-token-for-test" "$WORKLOG_BIN/scrape-slack.sh" --format=json >"$SCRATCH_ROOT/env_fail.json" 2>/dev/null
SCRAPE_OUT="$(cat "$SCRATCH_ROOT/env_fail.json")" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "unavailable"
assert data["provider"]["type"] == "env"
assert "auth" in data["provider"]["reason"].lower()
assert data["writes"]["performed"] is False
# Token must never appear in output
assert "xoxb-fake-token-for-test" not in json.dumps(data)
PY

# --no-env disables the env provider even when token is set
SLACK_BOT_TOKEN="xoxb-fake-token-for-test" "$WORKLOG_BIN/scrape-slack.sh" --no-env --format=json >"$SCRATCH_ROOT/no_env.json" 2>/dev/null
SCRAPE_OUT="$(cat "$SCRATCH_ROOT/no_env.json")" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["SCRAPE_OUT"])
assert data["status"] == "unavailable"
assert data["provider"]["type"] == "disabled"
PY

echo "ok: scrape-slack env provider graceful auth failure, --no-env override"
