import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const LEARNING_EVENT_SCHEMA_VERSION = "worklog.learning-event.v1";

function nowIso() {
  return new Date().toISOString();
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value || "")).digest("hex");
}

function relativeInside(root, value) {
  if (!value) return "";
  const rel = path.relative(root, value);
  return rel && !rel.startsWith("..") && !path.isAbsolute(rel) ? rel : "";
}

function learningFiles(config) {
  const dir = path.join(config.cacheDir, "learning");
  return {
    dir,
    events: path.join(dir, "refusals.jsonl"),
    notes: path.join(dir, "notes.md"),
  };
}

function refusalHint(code) {
  switch (code) {
    case "command.missing":
      return "Use a supported command word such as ask, plan, do, agent, dry-run, or an explicit Worklog-Command: ask trailer.";
    case "slug.missing":
      return "Mention a unique worklog slug or add Worklog-Slug: <slug>.";
    case "slug.ambiguous":
      return "Mention exactly one worklog slug or use Worklog-Slug: <slug>.";
    case "command.ambiguous":
      return "Use exactly one intent, or add Worklog-Command: ask|plan|do|agent.";
    case "identity.mismatch":
      return "Use the configured trusted GitHub login for this watcher.";
    case "repo.not_allowed":
      return "Use an issue in this instance's configured GitHub allowlist.";
    default:
      return "Inspect the local run artifact and adjust the issue/comment to satisfy the reported gate.";
  }
}

function targetFromResult(result) {
  const target = result.target || {};
  return {
    fullName: target.fullName || "",
    number: target.number || 0,
  };
}

function buildLearningEvent(config, result, at = nowIso()) {
  const dispatch = result.dispatch || null;
  const refusalCodes = (dispatch?.refusals || []).map((item) => item.code);
  return {
    schemaVersion: LEARNING_EVENT_SCHEMA_VERSION,
    at,
    instance: config.instance,
    worklogRepo: {
      basename: path.basename(config.worklogRepo),
      sha256: sha256(config.worklogRepo),
    },
    issueUrlHash: sha256(result.issueUrl || ""),
    target: targetFromResult(result),
    notModified: Boolean(result.notModified),
    cursorStatus: result.cursor?.status || null,
    runId: dispatch?.runId || "",
    runDir: relativeInside(config.stateDir, result.runDir || ""),
    dispatchState: dispatch?.state || (result.notModified ? "not_modified" : "unknown"),
    refusalCodes,
    intent: dispatch?.intent ? {
      slug: dispatch.intent.slug || "",
      command: dispatch.intent.command || "",
      sources: dispatch.intent.sources || {},
      source: {
        type: dispatch.intent.source?.type || "",
        author: dispatch.intent.source?.author || "",
        id: dispatch.intent.source?.id || "",
      },
      execute: {
        requested: Boolean(dispatch.intent.execute?.requested),
        target: dispatch.intent.execute?.target || "",
        source: dispatch.intent.execute?.source || "",
      },
    } : null,
    hints: refusalCodes.map(refusalHint),
  };
}

function appendRefusalNote(file, event) {
  if (!event.refusalCodes.length) return;
  const lines = [
    `- ${event.at} ${event.target.fullName}#${event.target.number} ${event.dispatchState}: ${event.refusalCodes.join(", ")}`,
    `  - run: ${event.runId || "(none)"}`,
    `  - next: ${event.hints.join(" ")}`,
  ];
  fs.appendFileSync(file, `${lines.join("\n")}\n`, { mode: 0o600 });
}

export function recordLearningEvent(config, result, options = {}) {
  const files = learningFiles(config);
  fs.mkdirSync(files.dir, { recursive: true, mode: 0o700 });
  const event = buildLearningEvent(config, result, options.at || nowIso());
  fs.appendFileSync(files.events, `${JSON.stringify(event)}\n`, { mode: 0o600 });
  appendRefusalNote(files.notes, event);
  return { event, files };
}
