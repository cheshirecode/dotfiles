#!/usr/bin/env bash
# Fixture-backed smoke test for the local-only worklog issue dispatch gate.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
SCRATCH="$(mktemp -d -t worklog-manager-dispatch-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

FIXTURE_REPO="$(pwd)/tests/worklog_manager/fixtures/projects"
CONFIG="$SCRATCH/instance.json"
BAD_SANDBOX_CONFIG="$SCRATCH/bad-sandbox-instance.json"
OUT_ACCEPTED="$SCRATCH/accepted.json"
OUT_DEFAULT="$SCRATCH/default.json"
OUT_COMMENT="$SCRATCH/comment.json"
OUT_ASK="$SCRATCH/ask.json"
OUT_AMBIG_READ_DO="$SCRATCH/ambiguous-read-do.json"
OUT_REFUSED="$SCRATCH/refused.json"
OUT_EXEC_REFUSED="$SCRATCH/execute-refused.json"
OUT_EXEC_PLANNED="$SCRATCH/execute-planned.json"
OUT_EXEC_FREEFORM="$SCRATCH/execute-freeform.json"
OUT_EXEC_BAD_SANDBOX="$SCRATCH/execute-bad-sandbox.json"
FAKE_SANDBOX="$SCRATCH/fake-sandbox.sh"
BAD_SANDBOX="$SCRATCH/not-executable-sandbox.sh"
FAKE_SANDBOX_LOG="$SCRATCH/fake-sandbox.log"

cat > "$FAKE_SANDBOX" <<'FAKE_SANDBOX'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${FAKE_SANDBOX_LOG:?}"
printf '\n' >> "${FAKE_SANDBOX_LOG:?}"
if [[ "${1:-}" != "run-headless" ]]; then
  echo "expected run-headless" >&2
  exit 91
fi
echo "runner payload:"
printf '%s\n' "$*"
echo "sandbox run-headless: exit=0 artifacts=/tmp/fake-sandbox-artifacts"
FAKE_SANDBOX
chmod +x "$FAKE_SANDBOX"
printf '#!/usr/bin/env bash\nexit 92\n' > "$BAD_SANDBOX"

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
    "command": "$FAKE_SANDBOX",
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

cat > "$BAD_SANDBOX_CONFIG" <<JSON
{
  "schemaVersion": "worklog-manager.instance.v1",
  "instance": "fixture-projects",
  "roots": {
    "worklogRepo": "$FIXTURE_REPO",
    "stateDir": "$SCRATCH/bad-sandbox-state",
    "cacheDir": "$SCRATCH/bad-sandbox-cache"
  },
  "github": {
    "repos": ["example/projects-ui"]
  },
  "sandbox": {
    "command": "$BAD_SANDBOX",
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

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
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

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
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

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
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

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/freeform-comment-ask.json \
  --output "$OUT_ASK"

node - "$OUT_ASK" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "planned") throw new Error("freeform ask comment should plan");
if (out.dispatch.intent.source.type !== "issue-comment") throw new Error("latest trusted ask comment was not selected");
if (out.dispatch.intent.source.id !== "ask-command-comment") throw new Error("wrong ask comment selected");
if (out.dispatch.intent.slug !== "projects-child") throw new Error("ask comment default slug not applied");
if (out.dispatch.intent.command !== "ask") throw new Error("read-only phrase did not infer ask");
if (out.dispatch.intent.sources.command !== "natural-language") throw new Error("unexpected ask command source");
if (out.dispatch.plan.execution.active) throw new Error("ask plan should not activate execution");
if (out.dispatch.plan.execution.approved) throw new Error("ask plan should not approve execution");
NODE

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --issue tests/worklog_manager/fixtures/freeform-ambiguous-read-do.json \
  --output "$OUT_AMBIG_READ_DO"

node - "$OUT_AMBIG_READ_DO" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "refused") throw new Error("mixed read and mutate intent should refuse");
if (!out.dispatch.refusals.some((item) => item.code === "command.ambiguous")) {
  throw new Error("missing command.ambiguous refusal");
}
if (out.dispatch.refusals.some((item) => item.code === "command.invalid")) {
  throw new Error("ambiguous command should not also be command.invalid");
}
NODE

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
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

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
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

set +e
FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$BAD_SANDBOX_CONFIG" \
  --execute \
  --issue tests/worklog_manager/fixtures/execute-agent.json \
  --output "$OUT_EXEC_BAD_SANDBOX" \
  2> "$SCRATCH/execute-bad-sandbox.err"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "non-executable sandbox command unexpectedly succeeded" >&2
  exit 1
fi
grep -q "requires an executable sandbox.command" "$SCRATCH/execute-bad-sandbox.err"

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --execute \
  --issue tests/worklog_manager/fixtures/execute-agent.json \
  --output "$OUT_EXEC_PLANNED"

node - "$OUT_EXEC_PLANNED" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "completed") throw new Error("confirmed agent should complete fake sandbox run");
if (!out.dispatch.plan.execution.approved) throw new Error("execution should be approved in the plan");
if (!out.dispatch.execution?.approved) throw new Error("execution result not approved");
if (out.dispatch.execution.status !== 0) throw new Error("fake sandbox did not exit 0");
if (out.dispatch.execution.runHeadless?.exitCode !== 0) throw new Error("run-headless summary not parsed");
if (!out.dispatch.statusComment.includes("sandbox execution completed")) {
  throw new Error("status did not identify sandbox execution completion");
}
NODE

FAKE_SANDBOX_LOG="$FAKE_SANDBOX_LOG" "$WORKLOG_BIN/worklog-manager" dispatch \
  --config "$CONFIG" \
  --execute \
  --issue tests/worklog_manager/fixtures/freeform-comment-execute.json \
  --output "$OUT_EXEC_FREEFORM"

node - "$OUT_EXEC_FREEFORM" <<'NODE'
const fs = require("node:fs");
const out = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (out.dispatch.state !== "completed") throw new Error("freeform sandbox comment should complete fake sandbox run");
if (out.dispatch.intent.source.type !== "issue-comment") throw new Error("trusted execution comment was not selected");
if (out.dispatch.intent.source.id !== "execute-command-comment") throw new Error("wrong execution comment selected");
if (out.dispatch.intent.slug !== "projects-child") throw new Error("freeform execution slug not inferred");
if (out.dispatch.intent.command !== "agent") throw new Error("freeform execution command not inferred");
if (out.dispatch.intent.sources.slug !== "natural-language") throw new Error("unexpected freeform execution slug source");
if (out.dispatch.intent.sources.command !== "natural-language") throw new Error("unexpected freeform execution command source");
if (out.dispatch.intent.execute.source !== "natural-language") throw new Error("sandbox execution confirmation was not inferred");
if (!out.dispatch.execution?.approved) throw new Error("freeform execution was not approved");
NODE

node - "$FAKE_SANDBOX_LOG" <<'NODE'
const fs = require("node:fs");
const log = fs.readFileSync(process.argv[2], "utf8");
if (!log.includes("run-headless node -e")) throw new Error("fake sandbox was not invoked with no-shell argv");
if (log.includes("accepted-plan")) throw new Error("sandbox log should not contain unrelated dry-run fixtures");
NODE

echo "worklog-manager dispatch fixture test passed"
