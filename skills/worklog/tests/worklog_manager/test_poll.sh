#!/usr/bin/env bash
# Fixture-backed smoke test for dry GitHub issue polling.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SCRATCH="$(mktemp -d -t worklog-manager-poll-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

FIXTURE_REPO="$(pwd)/tests/worklog_manager/fixtures/projects"
CONFIG="$SCRATCH/instance.json"
MISSING_LOGIN_CONFIG="$SCRATCH/missing-login-instance.json"
DISABLED_CONFIG="$SCRATCH/disabled-instance.json"
WATCHER_CONFIG="$SCRATCH/watcher-instance.json"
OSS_CONFIG="$SCRATCH/oss-instance.json"
COLLISION_CONFIG="$SCRATCH/collision-instance.json"
OUT_POLL="$SCRATCH/poll.json"
OUT_NOTMOD="$SCRATCH/not-modified.json"
OUT_POST="$SCRATCH/post-status.json"
OUT_REFUSED="$SCRATCH/refused.json"
OUT_VALIDATE="$SCRATCH/validate-watchers.json"
OUT_VALIDATE_BAD="$SCRATCH/validate-watchers-bad.json"
FAKE_BIN="$SCRATCH/bin"
FAKE_GH_LOG="$SCRATCH/gh.log"
mkdir -p "$FAKE_BIN"

cat > "$CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-projects",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/state",
    "cacheDir": "$SCRATCH/cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": "fixture"
  },
  "poll": {
    "enabled": true
  },
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$MISSING_LOGIN_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-projects-missing-login",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/missing-login-state",
    "cacheDir": "$SCRATCH/missing-login-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": ""
  },
  "poll": {
    "enabled": true
  },
  "daemon": {
    "defaultSlug": "projects-child",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$DISABLED_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-projects-disabled",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/disabled-state",
    "cacheDir": "$SCRATCH/disabled-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": "fixture"
  },
  "poll": {
    "enabled": false
  },
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$WATCHER_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-projects",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/watcher-state",
    "cacheDir": "$SCRATCH/watcher-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": "fixture"
  },
  "poll": {
    "enabled": true,
    "issueUrls": ["https://github.com/example/projects-ui/issues/9"]
  },
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$OSS_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-oss",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/oss-state",
    "cacheDir": "$SCRATCH/oss-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": "fixture"
  },
  "poll": {
    "enabled": false,
    "issueUrls": ["https://github.com/example/projects-ui/issues/9"]
  },
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$COLLISION_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-collision",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/collision-state",
    "cacheDir": "$SCRATCH/collision-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "/workspace/oss/sandbox/bin/sandbox.sh",
    "profile": "fixture"
  },
  "poll": {
    "enabled": true,
    "issueUrls": ["https://github.com/example/projects-ui/issues/9"]
  },
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
    "statusCommentMarker": "<!-- worklog-manager-status:fixture-projects -->",
    "commands": ["ask", "plan", "do", "agent"]
  }
}
JSON

cat > "$FAKE_BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "${FAKE_GH_LOG:?}"
printf '\n' >> "${FAKE_GH_LOG:?}"

for arg in "$@"; do
  if [[ "$arg" == "--method" && "${ALLOW_GH_METHOD:-}" != "PATCH" ]]; then
    echo "unexpected mutating gh call" >&2
    exit 97
  fi
done

joined=" $* "
if [[ "$joined" == *"--method PATCH"* ]]; then
  if [[ "$joined" != *"repos/example/projects-ui/issues/comments/100"* ]]; then
    echo "unexpected PATCH target: $*" >&2
    exit 96
  fi
  cat <<'JSON'
{
  "id": 100,
  "html_url": "https://github.com/example/projects-ui/issues/9#issuecomment-status"
}
JSON
  exit 0
fi

if [[ "$joined" == *"comments?per_page=100"* ]]; then
  cat <<'JSON'
[
  {
    "id": 100,
    "node_id": "status-comment",
    "body": "<!-- worklog-manager-status:fixture-projects -->\nworklog-manager: dry-run planned",
    "user": {"login": "fixture-user"},
    "html_url": "https://github.com/example/projects-ui/issues/9#issuecomment-status",
    "created_at": "2026-06-08T15:00:00Z",
    "updated_at": "2026-06-08T15:00:00Z"
  },
  {
    "id": 101,
    "node_id": "other-user-comment",
    "body": "Implement this now.",
    "user": {"login": "someone-else"},
    "html_url": "https://github.com/example/projects-ui/issues/9#issuecomment-other",
    "created_at": "2026-06-08T15:01:00Z",
    "updated_at": "2026-06-08T15:01:00Z"
  },
  {
    "id": 102,
    "node_id": "command-comment",
    "body": "Dry-run the polling smoke. Do not execute mutating work.",
    "user": {"login": "fixture-user"},
    "html_url": "https://github.com/example/projects-ui/issues/9#issuecomment-command",
    "created_at": "2026-06-08T15:02:00Z",
    "updated_at": "2026-06-08T15:02:00Z"
  }
]
JSON
  exit 0
fi

if [[ "$joined" == *"repos/example/projects-ui/issues/9"* ]]; then
  if [[ "$joined" == *"If-None-Match:"* ]]; then
    echo "HTTP 304 Not Modified" >&2
    exit 1
  fi
  cat <<'JSON'
HTTP/2 200
etag: W/"fixture-etag"

{
  "id": 9001,
  "node_id": "ISSUE_fixture_poll",
  "number": 9,
  "title": "Standing issue body",
  "body": "Use this issue for worklog-manager polling smoke checks.",
  "user": {"login": "fixture-user"},
  "labels": [{"name": "worklog-manager"}],
  "html_url": "https://github.com/example/projects-ui/issues/9"
}
JSON
  exit 0
fi

echo "unexpected gh api args: $*" >&2
exit 98
FAKE_GH
chmod +x "$FAKE_BIN/gh"

: > "$FAKE_GH_LOG"
set +e
PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$CONFIG" \
  --issue-url https://github.com/example/not-allowed/issues/9 \
  --force-fetch \
  --output "$OUT_REFUSED" \
  2> "$SCRATCH/refused-repo.err"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "disallowed repo poll unexpectedly succeeded" >&2
  exit 1
fi
grep -q "example/not-allowed" "$SCRATCH/refused-repo.err"
if [[ -s "$FAKE_GH_LOG" ]]; then
  echo "disallowed repo preflight should not call gh" >&2
  exit 1
fi

: > "$FAKE_GH_LOG"
set +e
PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$MISSING_LOGIN_CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --force-fetch \
  --output "$OUT_REFUSED" \
  2> "$SCRATCH/missing-login.err"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "missing expectedLogin poll unexpectedly succeeded" >&2
  exit 1
fi
grep -q "requires daemon.expectedLogin" "$SCRATCH/missing-login.err"
if [[ -s "$FAKE_GH_LOG" ]]; then
  echo "missing expectedLogin preflight should not call gh" >&2
  exit 1
fi

: > "$FAKE_GH_LOG"
set +e
PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$DISABLED_CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --force-fetch \
  --output "$OUT_REFUSED" \
  2> "$SCRATCH/disabled.err"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "disabled poll unexpectedly succeeded" >&2
  exit 1
fi
grep -q "poll.enabled=true" "$SCRATCH/disabled.err"
if [[ -s "$FAKE_GH_LOG" ]]; then
  echo "disabled poll preflight should not call gh" >&2
  exit 1
fi

"$WORKLOG_BIN/worklog-manager" validate-watchers \
  --config "$WATCHER_CONFIG" \
  --config "$OSS_CONFIG" \
  --output "$OUT_VALIDATE"

node - "$OUT_VALIDATE" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.schemaVersion !== "worklog.watcher-validation.v1") throw new Error("unexpected watcher validation schema");
if (!out.ok) throw new Error("projects+oss watcher validation should pass");
if (out.errors.length) throw new Error("unexpected watcher validation errors");
if (out.warnings.length) throw new Error("unexpected watcher validation warnings");
NODE

set +e
"$WORKLOG_BIN/worklog-manager" validate-watchers \
  --config "$WATCHER_CONFIG" \
  --config "$COLLISION_CONFIG" \
  --output "$OUT_VALIDATE_BAD" \
  2> "$SCRATCH/validate-bad.err"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "marker collision validation unexpectedly succeeded" >&2
  exit 1
fi
node - "$OUT_VALIDATE_BAD" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.ok) throw new Error("collision validation should fail");
if (!out.errors.some((item) => item.code === "poll.status_marker_collision")) {
  throw new Error("missing poll.status_marker_collision");
}
NODE

: > "$FAKE_GH_LOG"
PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --force-fetch \
  --output "$OUT_POLL"

node - "$OUT_POLL" "$FAKE_GH_LOG" "$SCRATCH" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const ghLog = fs.readFileSync(process.argv[3], "utf8");
const scratch = process.argv[4];
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
assert(out.notModified === false, "first poll should fetch issue");
assert(out.target.fullName === "example/projects-ui", "wrong target");
assert(out.comment === null, "dry poll must not post a comment");
assert(out.dispatch.state === "planned", "poll should plan dispatch");
assert(out.dispatch.intent.source.type === "issue-comment", "trusted comment not selected");
assert(out.dispatch.intent.source.id === "command-comment", "wrong command comment selected");
assert(out.dispatch.intent.command === "plan", "natural-language plan not inferred");
assert(fs.existsSync(out.cursor.file), "cursor artifact missing");
assert(fs.existsSync(`${out.runDir}/state.json`), "dispatch state artifact missing");
assert(fs.existsSync(`${out.runDir}/status-comment.md`), "status-comment artifact missing");
const learningFile = `${scratch}/cache/learning/refusals.jsonl`;
assert(fs.existsSync(learningFile), "learning event missing");
const learningText = fs.readFileSync(learningFile, "utf8");
assert(learningText.includes('"schemaVersion":"worklog.learning-event.v1"'), "unexpected learning schema");
assert(!learningText.includes("Dry-run the polling smoke"), "learning event leaked prompt");
assert(!learningText.includes("/Users/"), "learning event leaked host path");
assert(!ghLog.includes("--method"), "poll attempted a mutating gh call");
NODE

PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --output "$OUT_NOTMOD"

node - "$OUT_NOTMOD" "$FAKE_GH_LOG" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const ghLog = fs.readFileSync(process.argv[3], "utf8");
if (!out.notModified) throw new Error("second poll should be notModified");
if (out.cursor.status !== 304) throw new Error("cursor did not record 304");
if (out.dispatch) throw new Error("notModified poll should not dispatch");
if (ghLog.includes("--method")) throw new Error("poll attempted a mutating gh call");
NODE

PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" ALLOW_GH_METHOD=PATCH "$WORKLOG_BIN/worklog-manager" poll \
  --config "$CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --force-fetch \
  --post-status \
  --output "$OUT_POST"

node - "$OUT_POST" "$FAKE_GH_LOG" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const ghLog = fs.readFileSync(process.argv[3], "utf8");
if (out.comment?.action !== "updated") throw new Error("status comment was not updated");
if (out.comment?.id !== 100) throw new Error("wrong status comment id");
if (!ghLog.includes("--method PATCH")) throw new Error("post-status did not PATCH");
if (ghLog.includes("polling\\ smoke") || ghLog.includes("workspace") || ghLog.includes("runner-command")) {
  throw new Error("status comment leaked prompt or local artifact details");
}
NODE

echo "worklog-manager poll fixture test passed"
