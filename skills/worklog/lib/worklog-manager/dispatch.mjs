import childProcess from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { inferIssueIntent, issueFingerprint, normalizeIssue, redactedIssue, validateIntent } from "./issue.mjs";

export const DISPATCH_SCHEMA_VERSION = "worklog.issue-dispatch.v1";
export const RUNNER_RESULT_SCHEMA_VERSION = "worklog.runner-result.v1";

function nowIso() {
  return new Date().toISOString();
}

function transition(history, state, note = "", at = nowIso()) {
  history.push({ state, note, at });
}

function refusal(code, message) {
  return { code, message };
}

function safeSegment(value) {
  return String(value || "unknown").replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "unknown";
}

function runIdFor(issue, slug, fingerprint) {
  return [
    new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "Z"),
    safeSegment(issue.repository.replace("/", "-")),
    `issue-${issue.number || "unknown"}`,
    safeSegment(slug),
    fingerprint.slice(0, 10),
  ].join("-");
}

function taskExists(graph, slug) {
  return graph.nodes.some((node) => node.type === "task" && node.slug === slug);
}

function executionApproved(config, intent) {
  return Boolean(
    config.execute
    && config.daemon.execution.enabled
    && config.daemon.execution.commands.includes(intent.command)
    && intent.execute.requested
    && intent.execute.target === config.daemon.execution.confirmation
  );
}

function buildRunnerPayload(config, issue, intent) {
  const approved = executionApproved(config, intent);
  return {
    schemaVersion: RUNNER_RESULT_SCHEMA_VERSION,
    dryRun: !approved,
    issue: `${issue.repository}#${issue.number}`,
    slug: intent.slug,
    command: intent.command,
    execution: {
      active: Boolean(config.execute),
      requested: Boolean(intent.execute.requested),
      approved,
      target: intent.execute.target || "",
    },
  };
}

function buildSandboxPlan(config, issue, intent) {
  const command = config.sandbox.command || "bin/sandbox.sh";
  const payload = buildRunnerPayload(config, issue, intent);
  return {
    kind: "sandbox-run-headless",
    shell: false,
    timeoutSeconds: config.sandbox.timeoutSeconds,
    execution: payload.execution,
    argv: [
      command,
      "run-headless",
      "node",
      "-e",
      `console.log(${JSON.stringify(JSON.stringify(payload))})`,
    ],
  };
}

function parseRunHeadlessSummary(stdout) {
  const match = String(stdout || "").match(/sandbox run-headless: exit=(\d+) artifacts=(.+)\s*$/m);
  if (!match) return null;
  return {
    exitCode: Number(match[1]),
    artifacts: match[2].trim(),
  };
}

function validateAgainstConfig(config, graph, issue, intent, fingerprint) {
  const errors = [...validateIntent(intent)];
  if (config.expectedIssueHash && config.expectedIssueHash !== fingerprint) {
    errors.push(refusal("issue.drift", "Issue title/body hash changed since the run was planned."));
  }
  if (config.daemon.expectedLogin && issue.author !== config.daemon.expectedLogin) {
    errors.push(refusal("identity.mismatch", `Issue author '${issue.author}' does not match expected login '${config.daemon.expectedLogin}'.`));
  }
  if (!config.github.repos.includes(issue.repository)) {
    errors.push(refusal("repo.not_allowed", `Issue repository '${issue.repository}' is not in this instance allowlist.`));
  }
  if (intent.command && !config.daemon.commands.includes(intent.command)) {
    errors.push(refusal("command.not_allowed", `Command '${intent.command}' is not enabled for this instance.`));
  }
  if (intent.slug && !taskExists(graph, intent.slug)) {
    errors.push(refusal("slug.not_found", `No task node for slug '${intent.slug}' exists in this instance graph.`));
  }
  if (config.execute) {
    if (!config.daemon.execution.enabled) {
      errors.push(refusal("execution.disabled", "This instance does not enable sandbox execution."));
    }
    if (intent.command && !config.daemon.execution.commands.includes(intent.command)) {
      errors.push(refusal("execution.command_not_allowed", `Command '${intent.command}' is not enabled for sandbox execution.`));
    }
    if (!intent.execute.requested || intent.execute.target !== config.daemon.execution.confirmation) {
      errors.push(refusal("execution.confirmation_missing", `Issue must include Worklog-Execute: ${config.daemon.execution.confirmation} before --execute can run.`));
    }
  }
  return errors;
}

function publicStatus(dispatch) {
  const marker = dispatch.instance.statusCommentMarker;
  if (dispatch.state === "refused") {
    return [
      marker,
      "worklog-manager: refused",
      "",
      `Issue: ${dispatch.issue.repository}#${dispatch.issue.number}`,
      `Slug: ${dispatch.intent.slug || "(missing)"}`,
      `Reason: ${dispatch.refusals.map((item) => item.code).join(", ")}`,
      "",
      "Details are redacted; see local run artifacts on the daemon host.",
    ].join("\n");
  }
  const status = dispatch.state === "completed"
    ? dispatch.execution?.approved
      ? "sandbox execution completed"
      : "dry-run completed"
    : dispatch.state === "failed"
      ? dispatch.execution?.approved
        ? "sandbox execution failed"
        : "dry-run failed"
      : dispatch.plan?.execution?.approved
        ? "sandbox execution planned"
        : "dry-run planned";
  return [
    marker,
    `worklog-manager: ${status}`,
    "",
    `Issue: ${dispatch.issue.repository}#${dispatch.issue.number}`,
    `Slug: ${dispatch.intent.slug}`,
    `Command: ${dispatch.intent.command}`,
    `Runner: ${dispatch.plan.kind}`,
    "",
    "No secrets, prompt body, tokens, or local paths are posted here.",
  ].join("\n");
}

export function createDispatch(config, graph, issue) {
  issue = normalizeIssue(issue);
  const history = [];
  transition(history, "received", "issue loaded");
  const fingerprint = issueFingerprint(issue);
  const intent = inferIssueIntent(issue, graph, config);
  const refusals = validateAgainstConfig(config, graph, issue, intent, fingerprint);
  const runId = runIdFor(issue, intent.slug || "no-slug", fingerprint);
  const base = {
    schemaVersion: DISPATCH_SCHEMA_VERSION,
    runId,
    state: refusals.length ? "refused" : "planned",
    issueHash: fingerprint,
    issue: redactedIssue(issue),
    intent,
    instance: {
      name: config.instance,
      expectedLogin: config.daemon.expectedLogin,
      githubRepos: config.github.repos,
      statusCommentMarker: config.daemon.statusCommentMarker,
    },
    leases: {
      daemon: config.instance,
      issue: `${issue.repository}#${issue.number || "unknown"}`,
      slug: intent.slug || "",
    },
    history,
    refusals,
    plan: null,
  };

  if (refusals.length) {
    transition(history, "refused", refusals.map((item) => item.code).join(", "));
    base.statusComment = publicStatus(base);
    return base;
  }

  transition(history, "validated", "issue matched instance gates");
  transition(history, "leased", config.execute ? "sandbox execution lease materialized in local artifact" : "dry-run lease materialized in local artifact");
  base.plan = buildSandboxPlan(config, issue, intent);
  transition(history, "planned", "sandbox run-headless argv prepared without shell");
  base.statusComment = publicStatus(base);
  return base;
}

export function dispatchDir(config, dispatch) {
  return path.join(config.stateDir, "runs", dispatch.runId);
}

export function writeDispatchArtifacts(config, dispatch) {
  const dir = dispatchDir(config, dispatch);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.writeFileSync(path.join(dir, "state.json"), `${JSON.stringify(dispatch, null, 2)}\n`);
  fs.writeFileSync(path.join(dir, "status-comment.md"), `${dispatch.statusComment}\n`);
  if (dispatch.plan) {
    fs.writeFileSync(path.join(dir, "runner-command.json"), `${JSON.stringify(dispatch.plan, null, 2)}\n`);
  }
  return dir;
}

export function executeDispatch(config, dispatch) {
  if (!dispatch.plan) return dispatch;
  const [command, ...args] = dispatch.plan.argv;
  transition(dispatch.history, "running", "executing sandbox run-headless argv");
  const result = childProcess.spawnSync(command, args, {
    encoding: "utf8",
    shell: false,
    timeout: dispatch.plan.timeoutSeconds * 1000,
  });
  dispatch.execution = {
    approved: Boolean(dispatch.plan.execution?.approved),
    status: result.status,
    signal: result.signal,
    stdout: result.stdout,
    stderr: result.stderr,
    error: result.error ? result.error.message : "",
    runHeadless: parseRunHeadlessSummary(result.stdout),
  };
  dispatch.state = result.status === 0 ? "completed" : "failed";
  transition(dispatch.history, dispatch.state, result.status === 0 ? "runner exited 0" : "runner failed");
  dispatch.statusComment = publicStatus(dispatch);
  return dispatch;
}
