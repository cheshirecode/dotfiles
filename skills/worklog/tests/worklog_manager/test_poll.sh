#!/usr/bin/env bash
# Fixture-backed smoke test for dry GitHub issue polling.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SCRATCH="$(mktemp -d -t worklog-manager-poll-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

FIXTURE_REPO="$(pwd)/tests/worklog_manager/fixtures/projects"
CONFIG="$SCRATCH/instance.json"
OUT_POLL="$SCRATCH/poll.json"
OUT_NOTMOD="$SCRATCH/not-modified.json"
OUT_POST="$SCRATCH/post-status.json"
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
  "daemon": {
    "expectedLogin": "fixture-user",
    "defaultSlug": "projects-child",
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
    "body": "<!-- worklog-manager-status -->\nworklog-manager: dry-run planned",
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

PATH="$FAKE_BIN:$PATH" FAKE_GH_LOG="$FAKE_GH_LOG" "$WORKLOG_BIN/worklog-manager" poll \
  --config "$CONFIG" \
  --issue-url https://github.com/example/projects-ui/issues/9 \
  --force-fetch \
  --output "$OUT_POLL"

node - "$OUT_POLL" "$FAKE_GH_LOG" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const ghLog = fs.readFileSync(process.argv[3], "utf8");
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
