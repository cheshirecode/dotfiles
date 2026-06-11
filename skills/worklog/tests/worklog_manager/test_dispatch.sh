#!/usr/bin/env bash
# Fixture-backed smoke test for the local-only worklog issue dispatch gate.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SCRATCH="$(mktemp -d -t worklog-manager-dispatch-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

FIXTURE_REPO="$(pwd)/tests/worklog_manager/fixtures/projects"
CONFIG="$SCRATCH/instance.json"
OUT_ACCEPTED="$SCRATCH/accepted.json"
OUT_DEFAULT="$SCRATCH/default.json"
OUT_COMMENT="$SCRATCH/comment.json"
OUT_REFUSED="$SCRATCH/refused.json"
OUT_EXEC_REFUSED="$SCRATCH/execute-refused.json"
OUT_EXEC_PLANNED="$SCRATCH/execute-planned.json"

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
    "commands": ["ask", "plan", "do", "agent"],
    "execution": {
      "enabled": true,
      "commands": ["agent"],
      "confirmation": "sandbox"
    }
  }
}
JSON

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/accepted-plan.json \
  --output "$OUT_ACCEPTED"

node - "$OUT_ACCEPTED" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
assert(out.dispatch.schemaVersion === "worklog.issue-dispatch.v1", "unexpected dispatch schema");
assert(out.dispatch.state === "planned", "accepted fixture should plan");
assert(out.dispatch.intent.slug === "projects-child", "slug trailer not honored");
assert(out.dispatch.intent.command === "plan", "command trailer not honored");
assert(out.dispatch.refusals.length === 0, "accepted fixture had refusals");
assert(out.dispatch.plan.shell === false, "sandbox argv must be no-shell");
assert(out.dispatch.statusComment.includes("worklog-manager: dry-run planned"), "status comment not redacted/planned");
assert(!out.dispatch.statusComment.includes("Please plan the next safe step"), "prompt leaked into status comment");
assert(fs.existsSync(`${out.runDir}/state.json`), "state artifact missing");
assert(fs.existsSync(`${out.runDir}/status-comment.md`), "status artifact missing");
assert(fs.existsSync(`${out.runDir}/runner-command.json`), "runner artifact missing");
NODE

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/freeform-default-plan.json \
  --output "$OUT_DEFAULT"

node - "$OUT_DEFAULT" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "planned") throw new Error("freeform default should plan");
if (out.dispatch.intent.slug !== "projects-child") throw new Error("default slug not applied");
if (out.dispatch.intent.sources.slug !== "daemon.defaultSlug") throw new Error("unexpected slug source");
if (out.dispatch.intent.command !== "plan") throw new Error("natural-language plan not inferred");
NODE

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/freeform-comment-plan.json \
  --output "$OUT_COMMENT"

node - "$OUT_COMMENT" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "planned") throw new Error("freeform comment should plan");
if (out.dispatch.intent.source.type !== "issue-comment") throw new Error("latest trusted comment was not selected");
if (out.dispatch.intent.source.id !== "command-comment") throw new Error("wrong command comment selected");
if (out.dispatch.intent.source.author !== "fixture-user") throw new Error("wrong command author");
if (out.dispatch.intent.slug !== "projects-child") throw new Error("comment flow default slug not applied");
if (out.dispatch.intent.command !== "plan") throw new Error("comment flow natural-language plan not inferred");
if (out.dispatch.issue.commentCount !== 3) throw new Error("comment count not redacted onto issue summary");
NODE

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/refused-identity.json \
  --output "$OUT_REFUSED"

node - "$OUT_REFUSED" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "refused") throw new Error("identity mismatch should refuse");
if (!out.dispatch.refusals.some((item) => item.code === "identity.mismatch")) {
  throw new Error("missing identity.mismatch refusal");
}
if (out.dispatch.plan !== null) throw new Error("refused dispatch must not have a runner plan");
NODE

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --execute \
  --issue tests/worklog_manager/fixtures/execute-agent-missing-confirmation.json \
  --output "$OUT_EXEC_REFUSED"

node - "$OUT_EXEC_REFUSED" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "refused") throw new Error("missing confirmation should refuse");
if (!out.dispatch.refusals.some((item) => item.code === "execution.confirmation_missing")) {
  throw new Error("missing execution.confirmation_missing refusal");
}
NODE

"$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --execute \
  --issue tests/worklog_manager/fixtures/execute-agent.json \
  --output "$OUT_EXEC_PLANNED"

node - "$OUT_EXEC_PLANNED" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "planned") throw new Error("confirmed agent should plan");
if (!out.dispatch.plan.execution.approved) throw new Error("execution should be approved in the plan");
if (out.dispatch.execution) throw new Error("upstream dispatch gate must not execute sandbox");
if (!out.dispatch.statusComment.includes("sandbox execution planned")) {
  throw new Error("status did not identify sandbox execution plan");
}
NODE

echo "worklog-manager dispatch fixture test passed"
