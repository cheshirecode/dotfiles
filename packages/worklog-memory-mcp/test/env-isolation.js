#!/usr/bin/env node
// The child environment must come from the VAULT, not from the shell that
// launched the server.
//
// Why this test exists: run() used to pass `{ ...process.env }` straight to
// the worklog scripts. A session started in the dotfiles checkout carries the
// oss direnv scope — GIT_AUTHOR_NAME=cheshirecode, GH_TOKEN, NPM_TOKEN,
// WORKLOG_LDAP=oss. Serving the work vault from that session committed work
// tasks under the oss author, with the oss token in scope, into people/oss/.
//
// The probe is a FAKE bin directory whose checkpoint.sh prints its own
// environment, so the assertions read the exact env the vault scripts would
// have received. No real vault and no network are touched.

import { spawn } from "node:child_process";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const SERVER = process.env.WMM_SERVER || path.join(import.meta.dirname, "..", "server.js");
// direnv keys its allow store by the canonical path, and macOS mktemp hands
// back /var/... for /private/var/...; resolve so `direnv allow` below sticks.
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "wmm-envcheck-")));

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m) => { console.log(`  FAIL  ${m}`); fail++; };

// A bin/ whose checkpoint.sh dumps the environment it was handed.
const bin = path.join(scratch, "bin");
fs.mkdirSync(bin, { recursive: true });
fs.writeFileSync(path.join(bin, "_lib.sh"), 'resolve_ldap() { echo "${WORKLOG_LDAP:-probe}"; }\n');
fs.writeFileSync(path.join(bin, "checkpoint.sh"), '#!/usr/bin/env bash\nenv\n');
fs.chmodSync(path.join(bin, "checkpoint.sh"), 0o755);

// Everything a sibling vault's direnv scope would leak into this process.
const POISON = {
  GIT_AUTHOR_NAME: "poison-author",
  GIT_AUTHOR_EMAIL: "poison@author",
  GIT_COMMITTER_NAME: "poison-author",
  GH_TOKEN: "poison-gh-token",
  NPM_TOKEN: "poison-npm-token",
  NODE_AUTH_TOKEN: "poison-node-token",
  WORKLOG_NS: "poison-ns",
  WORKLOG_ORG: "poison-org",
};

function session(vault, extraEnv) {
  const child = spawn("node", [SERVER], {
    env: { ...process.env, ...POISON, ...extraEnv, WORKLOG_REPO: vault, WORKLOG_BIN: bin },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  let exited = null;
  child.stderr.on("data", (c) => { stderr += c; });
  child.on("exit", (code) => {
    exited = code;
    for (const [, resolve] of pending) resolve({ __exit: code });
    pending.clear();
  });
  let buffer = "";
  const pending = new Map();
  child.stdout.on("data", (chunk) => {
    buffer += chunk;
    let idx;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx); buffer = buffer.slice(idx + 1);
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
      } catch { /* non-JSON line */ }
    }
  });
  let nextId = 1;
  const request = (method, params) => new Promise((resolve, reject) => {
    if (exited !== null) return resolve({ __exit: exited });
    const id = nextId++;
    pending.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    setTimeout(() => { if (pending.has(id)) { pending.delete(id); reject(new Error(`timeout: ${method}\n${stderr}`)); } }, 30000);
  });
  return {
    async init() {
      await request("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "envcheck", version: "0" } });
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
    },
    call: (name, args) => request("tools/call", { name, arguments: args }),
    stderr: () => stderr,
    close: () => child.kill(),
  };
}

// Run memory_task_create and return the env dump checkpoint.sh printed.
async function childEnvOf(vault, extraEnv, slug) {
  const s = session(vault, extraEnv);
  await s.init();
  const res = await s.call("memory_task_create", {
    slug, kind: "spike", context: "env isolation probe", next_action: "assert the env",
  });
  s.close();
  if (res.__exit !== undefined) {
    throw new Error(`server exited with ${res.__exit} before answering\n${s.stderr()}`);
  }
  const dump = res.result?.content?.[0]?.text || "";
  const env = {};
  for (const line of dump.split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) env[line.slice(0, i)] = line.slice(i + 1);
  }
  return env;
}

// --- Case 1: a vault with no .envrc of its own ------------------------------
// Credentials and git identity from the launching shell must not reach the
// scripts. WORKLOG_LDAP has no other source here, so the process value stands.
const plain = path.join(scratch, "vault-plain");
fs.mkdirSync(plain, { recursive: true });
const e1 = await childEnvOf(plain, { WORKLOG_LDAP: "configured" }, "probe-plain");

const leaked = ["GH_TOKEN", "NPM_TOKEN", "NODE_AUTH_TOKEN", "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "WORKLOG_NS", "WORKLOG_ORG"]
  .filter((k) => e1[k] !== undefined);
if (leaked.length === 0) ok("no-envrc vault: no shell credentials or git identity reach the scripts");
else bad(`no-envrc vault leaked ${leaked.map((k) => `${k}=${e1[k]}`).join(", ")}`);

if (e1.WORKLOG_REPO === plain) ok("no-envrc vault: WORKLOG_REPO points at the served vault");
else bad(`WORKLOG_REPO was ${e1.WORKLOG_REPO}, expected ${plain}`);

if (e1.WORKLOG_LDAP === "configured") ok("no-envrc vault: the configured namespace is used");
else bad(`WORKLOG_LDAP was ${e1.WORKLOG_LDAP}, expected "configured"`);

// --- Case 2: a vault that carries its own .envrc ----------------------------
// This is the work vault's shape: it unsets WORKLOG_LDAP on purpose so the
// namespace resolves from git email, and it exports the org identifiers. The
// vault's file must beat anything ambient.
let direnv = true;
try { execFileSync("direnv", ["version"], { stdio: "ignore" }); } catch { direnv = false; }

if (!direnv) {
  console.error("env-isolation NOT RUN for the .envrc case — direnv is not installed, so nothing was asserted about it.");
  process.exit(2);
}

const scoped = path.join(scratch, "vault-envrc");
fs.mkdirSync(scoped, { recursive: true });
fs.writeFileSync(path.join(scoped, ".envrc"), [
  "unset WORKLOG_LDAP",
  "unset WORKLOG_NS",
  'export WORKLOG_ORG="from-the-vault"',
  'export WORKLOG_IDENTITY_DOMAIN="vault.example"',
  "",
].join("\n"));
execFileSync("direnv", ["allow", scoped], { stdio: "ignore" });

const e2 = await childEnvOf(scoped, { WORKLOG_LDAP: "ambient-oss" }, "probe-scoped");

if (e2.WORKLOG_ORG === "from-the-vault") ok(".envrc vault: org identifiers come from the vault, not the shell");
else bad(`WORKLOG_ORG was ${e2.WORKLOG_ORG}, expected "from-the-vault"`);

if (e2.WORKLOG_LDAP === undefined) ok(".envrc vault: its `unset WORKLOG_LDAP` wins over the ambient namespace");
else bad(`WORKLOG_LDAP was ${e2.WORKLOG_LDAP}, expected unset — verify_provenance is disabled while it is set`);

if (e2.GH_TOKEN === undefined && e2.GIT_AUTHOR_NAME === undefined) ok(".envrc vault: no shell credentials or git identity reach the scripts");
else bad(`.envrc vault leaked GH_TOKEN=${e2.GH_TOKEN} GIT_AUTHOR_NAME=${e2.GIT_AUTHOR_NAME}`);

// The task file must land under the namespace the VAULT resolved. The probe
// _lib.sh echoes $WORKLOG_LDAP or "probe", so an ambient namespace that got
// through shows up as a people/ambient-oss/ directory.
const resolvedDir = path.join(scoped, "people", "probe", "active", "probe-scoped.md");
const strayNs = fs.existsSync(path.join(scoped, "people"))
  ? fs.readdirSync(path.join(scoped, "people")).filter((d) => d !== "probe")
  : [];
if (fs.existsSync(resolvedDir) && strayNs.length === 0) ok(".envrc vault: the task lands under the namespace the vault resolved");
else bad(`expected people/probe/active/probe-scoped.md only; stray namespaces: ${strayNs.join(", ") || "none"}`);

fs.rmSync(scratch, { recursive: true, force: true });
console.log(`env-isolation: ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
