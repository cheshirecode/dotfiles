import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { parseArgs, loadConfig } from "../../lib/worklog-manager/config.mjs";
import { extractGraph } from "../../lib/worklog-manager/extract.mjs";
import { parseIssueUrl } from "../../lib/worklog-manager/github.mjs";
import { refusalHint } from "../../lib/worklog-manager/hints.mjs";
import { inferIssueIntent, normalizeIssue, validateIntent } from "../../lib/worklog-manager/issue.mjs";
import { orderNextActions } from "../../lib/worklog-manager/render.mjs";
import { runIssueDispatch } from "../../lib/worklog-manager/runs.mjs";
import { validateWatcherConfigs } from "../../lib/worklog-manager/watchers.mjs";

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "worklog-manager-units-"));
}

function writeFile(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

function managerConfig(tmp, overrides = {}) {
  return {
    instance: "unit-instance",
    worklogRepo: path.join(tmp, "repo"),
    stateDir: path.join(tmp, "state"),
    cacheDir: path.join(tmp, "cache"),
    github: { repos: ["example/projects-ui"] },
    sandbox: { command: "", timeoutSeconds: 900 },
    poll: { enabled: true, issueUrls: [] },
    daemon: {
      expectedLogin: "fixture-user",
      commands: ["ask", "plan", "do", "agent"],
      defaultSlug: "",
      statusCommentMarker: "<!-- worklog-manager-status:unit-instance -->",
      execution: {
        enabled: false,
        commands: ["agent"],
        confirmation: "sandbox",
      },
    },
    expectedIssueHash: "",
    execute: false,
    postStatus: false,
    forceFetch: false,
    ...overrides,
  };
}

test("parseArgs and loadConfig preserve ordered poll issue URLs", () => {
  const tmp = tempDir();
  const configFile = path.join(tmp, "instance.json");
  writeFile(configFile, JSON.stringify({
    roots: {
      worklogRepo: "repo",
      stateDir: "state",
      cacheDir: "cache",
    },
    github: { repos: ["example/projects-ui"] },
    poll: {
      enabled: true,
      issueUrls: ["https://github.com/example/projects-ui/issues/1"],
    },
  }));

  const args = parseArgs([
    "poll",
    "--config", configFile,
    "--issue-url", "https://github.com/example/projects-ui/issues/2",
    "--iterations", "2",
  ]);
  const config = loadConfig(args, tmp);

  assert.equal(config.worklogRepo, path.join(tmp, "repo"));
  assert.deepEqual(config.poll.issueUrls, [
    "https://github.com/example/projects-ui/issues/1",
    "https://github.com/example/projects-ui/issues/2",
  ]);
  assert.equal(config.poll.iterations, 2);
});

test("inferIssueIntent resolves slug and non-mutating plan intent", () => {
  const graph = { nodes: [{ type: "task", slug: "projects-child" }] };
  const config = managerConfig(tempDir());
  const issue = normalizeIssue({
    id: "issue-1",
    number: 1,
    title: "Plan projects child",
    body: "Dry-run projects child. Do not execute mutating work.",
    repository: "example/projects-ui",
    author: "fixture-user",
  });

  const intent = inferIssueIntent(issue, graph, config);

  assert.equal(intent.slug, "projects-child");
  assert.equal(intent.sources.slug, "natural-language");
  assert.equal(intent.command, "plan");
  assert.equal(intent.sources.command, "natural-language");
  assert.equal(intent.execute.requested, false);
  assert.deepEqual(validateIntent(intent), []);
});

test("inferIssueIntent reports ambiguous command instead of guessing", () => {
  const graph = { nodes: [{ type: "task", slug: "projects-child" }] };
  const config = managerConfig(tempDir());
  const issue = normalizeIssue({
    id: "issue-2",
    number: 2,
    title: "Mixed request",
    body: "Show and implement projects-child.",
    repository: "example/projects-ui",
    author: "fixture-user",
  });

  const intent = inferIssueIntent(issue, graph, config);

  assert.equal(intent.command, "");
  assert.ok(intent.errors.some((error) => error.code === "command.ambiguous"));
  assert.ok(validateIntent(intent).some((error) => error.code === "command.ambiguous"));
});

test("extractGraph emits diagnostics for missing, duplicate, and unresolved task data", () => {
  const tmp = tempDir();
  const repo = path.join(tmp, "repo");
  const active = path.join(repo, "people", "fredtran", "active");
  writeFile(path.join(active, "nofrontmatter.md"), "No frontmatter here.\n");
  writeFile(path.join(active, "one.md"), `---
slug: one
status: in-progress
kind: impl
project: none
last_updated: 2026-06-08
next_action: "Do one."
related:
  - slug: missing-task
    note: unresolved fixture
---

## Context

One.
`);
  writeFile(path.join(active, "zzz-duplicate.md"), `---
slug: one
status: draft
kind: impl
project: none
last_updated: 2026-06-08
next_action: "Duplicate."
---

## Context

Duplicate.
`);

  const graph = extractGraph(loadConfig(parseArgs(["graph", "--repo", repo, "--format", "json"]), tmp));
  const codes = graph.diagnostics.map((item) => item.code);

  assert.ok(codes.includes("frontmatter.missing"));
  assert.ok(codes.includes("slug.duplicate"));
  assert.ok(codes.includes("edge.unresolved"));
});

test("validateWatcherConfigs warns on shared issue with different status markers", () => {
  const tmp = tempDir();
  const sharedIssue = "https://github.com/example/projects-ui/issues/9";
  const result = validateWatcherConfigs([
    {
      instance: "projects",
      stateDir: path.join(tmp, "projects-state"),
      cacheDir: path.join(tmp, "projects-cache"),
      poll: { enabled: true, issueUrls: [sharedIssue] },
      daemon: { statusCommentMarker: "<!-- projects -->" },
    },
    {
      instance: "oss",
      stateDir: path.join(tmp, "oss-state"),
      cacheDir: path.join(tmp, "oss-cache"),
      poll: { enabled: true, issueUrls: [sharedIssue] },
      daemon: { statusCommentMarker: "<!-- oss -->" },
    },
  ]);

  assert.equal(result.ok, true);
  assert.equal(result.errors.length, 0);
  assert.ok(result.warnings.some((item) => item.code === "poll.issue_url_shared"));
});

test("parseIssueUrl accepts GitHub issue URLs and rejects unsupported URLs", () => {
  assert.deepEqual(parseIssueUrl("https://github.com/example/projects-ui/issues/9#comment"), {
    owner: "example",
    repo: "projects-ui",
    number: 9,
    fullName: "example/projects-ui",
  });
  assert.throws(() => parseIssueUrl("https://github.com/example/projects-ui/pull/9"), /Unsupported GitHub issue URL/);
});

test("runIssueDispatch writes planned artifacts through the shared orchestration path", () => {
  const tmp = tempDir();
  const config = managerConfig(tmp);
  const graph = { nodes: [{ type: "task", slug: "projects-child" }] };
  const issue = {
    id: "issue-9",
    number: 9,
    title: "Plan work",
    body: "Worklog-Slug: projects-child\nWorklog-Command: plan\nPlease plan the next safe step.",
    repository: { full_name: "example/projects-ui" },
    author: { login: "fixture-user" },
    labels: [],
    html_url: "https://github.com/example/projects-ui/issues/9",
  };

  const { runDir, dispatch } = runIssueDispatch(config, graph, issue);

  assert.equal(dispatch.state, "planned");
  assert.equal(dispatch.intent.slug, "projects-child");
  assert.ok(fs.existsSync(path.join(runDir, "state.json")));
  assert.ok(fs.existsSync(path.join(runDir, "status-comment.md")));
  assert.ok(fs.existsSync(path.join(runDir, "runner-command.json")));
});

test("refusalHint exposes public-safe recovery guidance", () => {
  assert.match(refusalHint("identity.mismatch"), /trusted GitHub login/);
  assert.match(refusalHint("execution.confirmation_missing"), /sandbox execution confirmation/);
});

test("orderNextActions filters no-action tasks and sorts by status priority then date then slug", () => {
  const nodes = [
    { id: "draft-none", type: "task", state: "active", status: "draft", slug: "draft-none", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-01", next_action: "None — reference doc, no follow-up action" } },
    { id: "draft-empty", type: "task", state: "active", status: "draft", slug: "draft-empty", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-01" } },
    { id: "draft-actionable", type: "task", state: "active", status: "draft", slug: "draft-actionable", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-02", next_action: "Start implementation" } },
    { id: "blocked-waiting", type: "task", state: "active", status: "blocked", slug: "blocked-waiting", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-02", next_action: "Waiting on upstream" } },
    { id: "review-old", type: "task", state: "active", status: "in-review", slug: "review-old", project: "p", file: "f",
      frontmatter: { last_updated: "2026-06-01", next_action: "Watch CI" } },
    { id: "ship-recent", type: "task", state: "active", status: "shipping", slug: "ship-recent", project: "p", file: "f",
      frontmatter: { last_updated: "2026-06-20", next_action: "Final ack" } },
    { id: "progress-recent", type: "task", state: "active", status: "in-progress", slug: "progress-recent", project: "p", file: "f",
      frontmatter: { last_updated: "2026-06-20", next_action: "Keep coding" } },
    { id: "progress-older", type: "task", state: "active", status: "in-progress", slug: "progress-older", project: "p", file: "f",
      frontmatter: { last_updated: "2026-06-10", next_action: "Older step" } },
    { id: "archived-task", type: "task", state: "archived", status: "done", slug: "archived-task", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-02", next_action: "Done" } },
    { id: "project-node", type: "project", state: "active", status: "project", slug: "proj", project: "p", file: "f",
      frontmatter: { last_updated: "2026-07-02", next_action: "Project-level" } },
  ];

  const ordered = orderNextActions(nodes);
  const ids = ordered.map((n) => n.id);

  assert.deepEqual(ids, [
    "progress-recent",
    "progress-older",
    "ship-recent",
    "review-old",
    "draft-actionable",
    "blocked-waiting",
  ], "in-progress(2, date-desc) > shipping > in-review > draft > blocked; no-action drafts excluded; archived/project excluded");
});
