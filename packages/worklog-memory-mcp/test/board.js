#!/usr/bin/env node
// Both interfaces operate on one disposable Git vault, with no sync database.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import http from "node:http";
import { execFileSync } from "node:child_process";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const root = path.resolve(import.meta.dirname, "../../..");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "worklog-board-e2e-"));
const vault = path.join(scratch, "vault");
const bare = path.join(scratch, "origin.git");
const home = path.join(scratch, "home");
fs.mkdirSync(home);
const git = (...args) => execFileSync("git", args, { stdio: "pipe" });
const client = new Client({ name: "board-e2e", version: "1" });
let started = false, pass = 0;
const check = (label, fn) => { fn(); pass++; console.log(`  PASS  ${label}`); };
const call = (name, args) => client.callTool({ name, arguments: args }, undefined, { timeout: 120000 });
const text = result => result.content.map(c => c.text || "").join("\n");
let url, token;
async function state() { return fetch(`${url}/api/state`).then(r => r.json()); }
async function post(name, args, headers = {}) {
  return fetch(`${url}/api/tool`, { method: "POST", headers: { "Content-Type": "application/json", "X-Worklog-Token": token, ...headers },
    body: JSON.stringify({ name, arguments: args }) });
}
try {
  git("init", "-q", "--bare", bare);
  git("clone", "-q", bare, vault);
  git("-C", vault, "config", "user.name", "board-test");
  git("-C", vault, "config", "user.email", "oss@test");
  git("-C", vault, "config", "worklog.namespace", "oss");
  fs.mkdirSync(path.join(vault, "people/oss/active"), { recursive: true });
  fs.writeFileSync(path.join(vault, ".gitignore"), ".cache/\n");
  git("-C", vault, "add", ".gitignore");
  git("-C", vault, "commit", "-qm", "Seed disposable board vault");
  git("-C", vault, "push", "-qu", "origin", "HEAD");
  await client.connect(new StdioClientTransport({ command: process.execPath, args: [path.join(root, "packages/worklog-memory-mcp/server.js")],
    env: { ...process.env, HOME: home, XDG_CACHE_HOME: path.join(scratch, "cache"), WORKLOG_REPO: vault, WORKLOG_LDAP: "oss" }, stderr: "pipe" }));
  const created = await call("memory_task_create", { slug: "shared-card", kind: "impl", context: "Ship the shared board", next_action: "Build the board" });
  assert.equal(created.isError, false, text(created));
  const board = JSON.parse(text(await call("memory_board", {})));
  started = true; url = board.url;
  const again = JSON.parse(text(await call("memory_board", {})));
  check("repeated board start reuses one local process and URL", () => { assert.equal(again.pid, board.pid); assert.equal(again.url, url); assert.match(url, /^http:\/\/127\.0\.0\.1:/); });
  const initial = await state(); token = initial.token;
  check("board reads the task created through MCP", () => assert.equal(initial.tasks.find(t => t.slug === "shared-card").title, "Ship the shared board"));
  const updated = await call("memory_update_status", { slug: "shared-card", status: "ready" });
  assert.equal(updated.isError, false, text(updated));
  let next;
  for (let i = 0; i < 25; i++) {
    next = await state();
    if (next.tasks.find(t => t.slug === "shared-card").status === "ready") break;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  check("MCP status change appears on the board within five seconds", () => assert.equal(next.tasks.find(t => t.slug === "shared-card").status, "ready"));
  const response = await post("memory_update_status", { slug: "shared-card", status: "blocked", next_action: "API review" });
  assert.equal(response.status, 200, await response.text());
  const context = await call("memory_context", { slug: "shared-card" });
  check("board status and next step are immediately readable through MCP", () => { assert.match(text(context), /blocked/); assert.match(text(context), /Waiting on API review/); });
  const file = path.join(vault, "people/oss/active/shared-card.md");
  const before = fs.readFileSync(file, "utf8");
  const denied = await post("memory_update_status", { slug: "shared-card", status: "shipping" }, { Origin: "https://untrusted.example" });
  const noToken = await post("memory_update_status", { slug: "shared-card", status: "shipping" }, { "X-Worklog-Token": "wrong" });
  check("foreign-origin and tokenless writes leave task bytes unchanged", () => { assert.equal(denied.status, 403); assert.equal(noToken.status, 403); assert.equal(fs.readFileSync(file, "utf8"), before); });
  const hostStatus = await new Promise((resolve, reject) => {
    const req = http.get(`${url}/api/state`, { headers: { Host: "untrusted.example" } }, res => { res.resume(); resolve(res.statusCode); });
    req.on("error", reject);
  });
  check("foreign Host cannot read the board", () => assert.equal(hostStatus, 403));
  await call("memory_claim", { slug: "shared-card", session_id: "agent-owner" });
  const foreignWrite = await post("memory_update_status", { slug: "shared-card", status: "archived", session_id: "browser-other" });
  check("UI cannot complete a different agent's claimed task", () => assert.equal(foreignWrite.status, 409));
  const completed = await call("memory_update_status", { slug: "shared-card", status: "archived", session_id: "agent-owner", summary: "Board and MCP use the same record" });
  check("agents can complete their owned tasks without human approval", () => { assert.equal(completed.isError, false, text(completed)); assert.ok(!fs.existsSync(file)); assert.ok(fs.existsSync(path.join(vault, "people/oss/archive/shared-card.md"))); });
  let done;
  for (let i = 0; i < 25; i++) {
    done = await state();
    if (done.tasks.find(t => t.slug === "shared-card")?.archived) break;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  check("agent completion appears in the board's Done column data", () => assert.equal(done.tasks.find(t => t.slug === "shared-card").status, "archived"));
  await call("memory_board", { action: "stop" }); started = false;
  const stopped = JSON.parse(text(await call("memory_board", { action: "status" })));
  check("stop removes only the vault's board instance", () => assert.equal(stopped.running, false));
  console.log(`board: ${pass} pass, 0 fail`);
} finally {
  if (started) await call("memory_board", { action: "stop" });
  await client.close();
  fs.rmSync(scratch, { recursive: true, force: true });
}
