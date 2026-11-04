#!/usr/bin/env node
// Real protocol, Git, and project helper operations against a disposable vault.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const root = path.resolve(import.meta.dirname, "../../..");
const bin = path.join(root, "skills/worklog/bin");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "wmm-projects-"));
const vault = path.join(scratch, "vault");
const bare = path.join(scratch, "origin.git");
const git = (...args) => execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
const clients = [];
let passed = 0;
function check(label, fn) { fn(); passed++; console.log(`  PASS  ${label}`); }
async function connect(dir = vault) {
  const client = new Client({ name: "project-e2e", version: "1" });
  await client.connect(new StdioClientTransport({
    command: process.execPath, args: [path.join(root, "packages/worklog-memory-mcp/server.js")],
    env: { ...process.env, WORKLOG_REPO: dir, WORKLOG_BIN: bin, WORKLOG_LDAP: "oss", CLAUDE_CODE_SESSION_ID: "same-ambient-session" },
    stderr: "pipe",
  }));
  clients.push(client);
  return client;
}
const call = (client, name, args) => client.callTool({ name, arguments: args }, undefined, { timeout: 120000 });
const output = result => result.content.map(c => c.text || "").join("\n");
const taskPath = (slug, ns = "oss") => path.join(vault, "people", ns, "active", `${slug}.md`);
function task(slug, extra = "", ns = "oss") {
  fs.mkdirSync(path.dirname(taskPath(slug, ns)), { recursive: true });
  fs.writeFileSync(taskPath(slug, ns), `---\nslug: ${slug}\nstatus: draft\nkind: impl\nproject: test-project\nlast_updated: 2026-11-04\nnext_action: Run the test\n${extra}---\n\n## Context\n\nProject claim test.\n`);
}
try {
  git("init", "-q", "--bare", bare);
  git("clone", "-q", bare, vault);
  git("-C", vault, "config", "user.name", "mcp-test");
  git("-C", vault, "config", "user.email", "oss@test");
  git("-C", vault, "config", "worklog.namespace", "oss");
  fs.mkdirSync(path.join(vault, "people/oss/archive"), { recursive: true });
  task("first", "parent_slug: test-project\n");
  task("blocked-child", "parent_slug: test-project\n");
  task("foreign", "", "other");
  fs.writeFileSync(taskPath("test-project"), "---\nslug: test-project\nstatus: draft\nkind: project\nlast_updated: 2026-11-04\nnext_action: Claim a child\ntasks:\n  - slug: first\n  - slug: blocked-child\n    depends_on: [first]\n---\n\n## Context\n\nClaim tests.\n");
  git("-C", vault, "add", "people");
  git("-C", vault, "commit", "-qm", "Seed isolated protocol test");
  git("-C", vault, "push", "-qu", "origin", "HEAD");
  const a = await connect(), b = await connect();
  const next = await call(a, "memory_next", { project: "test-project" });
  check("next is read-only and dependency-ready", () => {
    assert.equal(next.isError, false); assert.match(output(next), /first/);
    assert.doesNotMatch(fs.readFileSync(taskPath("first"), "utf8"), /^claim:/m);
  });
  const blocked = await call(a, "memory_claim", { slug: "blocked-child", session_id: "a" });
  check("explicit task claims cannot bypass dependencies", () => assert.equal(blocked.isError, true));
  const race = await Promise.all([
    call(a, "memory_claim", { project: "test-project", session_id: "a" }),
    call(b, "memory_claim", { project: "test-project", session_id: "b" }),
  ]);
  check("two protocol sessions acquire one task only once", () => assert.equal(race.filter(r => !r.isError).length, 1));
  let owner = race[0].isError ? "b" : "a";
  const loser = owner === "a" ? "b" : "a";
  const before = fs.readFileSync(taskPath("first"), "utf8");
  await call(b, "memory_release", { slug: "first", session_id: loser });
  const denied = await call(b, "memory_checkpoint", { slug: "first", session_id: loser, evidence: "command: denied — must not write" });
  check("another session cannot release or checkpoint the claim", () => {
    assert.equal(denied.isError, true); assert.equal(fs.readFileSync(taskPath("first"), "utf8"), before);
  });
  const restarted = await connect();
  const renewed = await call(restarted, "memory_claim", { slug: "first", session_id: owner });
  check("claim owner can renew after a client restart", () => assert.equal(renewed.isError, false));
  const beforeInvalid = fs.readFileSync(taskPath("first"), "utf8");
  const invalid = await call(a, "memory_checkpoint", { slug: "first", session_id: owner, evidence: "untyped claim of success" });
  check("invalid evidence leaves task bytes unchanged", () => {
    assert.equal(invalid.isError, true); assert.equal(fs.readFileSync(taskPath("first"), "utf8"), beforeInvalid);
  });
  const saved = await call(a, "memory_checkpoint", { slug: "first", session_id: owner, evidence: "command: project test — owned checkpoint", status: "shipping", next_action: "Human review required" });
  check("owner checkpoints evidence and updates status", () => assert.equal(saved.isError, false));
  const foreignBefore = fs.readFileSync(taskPath("foreign", "other"), "utf8");
  const foreign = await call(a, "memory_claim", { slug: "foreign", session_id: owner });
  check("claims cannot write another namespace", () => {
    assert.equal(foreign.isError, true); assert.equal(fs.readFileSync(taskPath("foreign", "other"), "utf8"), foreignBefore);
  });
  const compact = await call(a, "memory_context", { slug: "first" });
  check("context defaults to compact resume format", () => assert.match(output(compact), /worklog-context\/v1/));
  for (let i = 0; i < 30; i++) fs.appendFileSync(taskPath("first"), `\nneedle ${i} ${"x".repeat(120)}`);
  const bounded = await call(a, "memory_search", { pattern: "needle", top: 2, max_chars: 256 });
  check("search bounds output and gives a recovery action", () => {
    assert.match(output(bounded), /truncated|more hits/); assert.ok(output(bounded).length < 600);
  });
  // Restore only this fixture file before native user acceptance.
  git("-C", vault, "restore", "people/oss/active/first.md");
  fs.writeFileSync(taskPath("first"), fs.readFileSync(taskPath("first"), "utf8").replace(/heartbeat_at: .*/, 'heartbeat_at: "2000-01-01T00:00:00Z"'));
  const recovered = await call(b, "memory_claim", { slug: "first", session_id: loser });
  check("a stopped session's expired claim can be recovered", () => {
    assert.equal(recovered.isError, false); assert.match(fs.readFileSync(taskPath("first"), "utf8"), new RegExp(`mcp:${loser}`));
  });
  owner = loser;
  const completed = await call(a, "memory_archive", { slug: "first", reason: "shipped", summary: "Completed by the owning agent", session_id: owner });
  check("an agent can complete its own claimed task", () => assert.equal(completed.isError, false));
  const ready = await call(a, "memory_next", { project: "test-project" });
  check("agent completion unlocks the dependent task", () => assert.match(output(ready), /blocked-child/));
  const second = path.join(scratch, "second-machine");
  git("clone", "-q", bare, second);
  git("-C", second, "config", "user.name", "mcp-test");
  git("-C", second, "config", "user.email", "oss@test");
  git("-C", second, "config", "worklog.namespace", "oss");
  const otherMachine = await connect(second);
  const remoteRace = await Promise.all([
    call(a, "memory_claim", { slug: "blocked-child", session_id: "machine-a" }),
    call(otherMachine, "memory_claim", { slug: "blocked-child", session_id: "machine-b" }),
  ]);
  check("separate Git clones do not both report a successful claim", () => assert.equal(remoteRace.filter(r => !r.isError).length, 1));
  console.log(`projects: ${passed} pass, 0 fail`);
} finally {
  await Promise.allSettled(clients.map(c => c.close()));
  fs.rmSync(scratch, { recursive: true, force: true });
}
