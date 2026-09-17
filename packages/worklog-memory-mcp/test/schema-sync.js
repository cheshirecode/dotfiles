#!/usr/bin/env node
// The MCP's task-file vocabulary must be the vault's vocabulary.
//
// Why this test exists: the frontmatter template and its enums lived in
// server.js while bin/_lint.py kept its own copies. _lint.py accepted 19
// kinds; server.js hardcoded 8. Eleven kinds valid in the vault could not be
// written through the MCP at all. Measured 2026-09-17: two of ten
// memory_task_create calls writing a real plan were rejected on `kind`, and
// the drift hid whether the kind was wrong or merely unreachable.
//
// The two status sets are checked separately and MUST differ. `valid` is what
// may exist in a committed file; `agent_writable` is what a tool may set.
// Asserting one merged list would certify nothing — see the schema's comment.

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const SERVER = process.env.WMM_SERVER || path.join(import.meta.dirname, "..", "server.js");
const pkg = path.join(import.meta.dirname, "..");
const SCHEMA = process.env.WORKLOG_TASK_SCHEMA
  || path.join(pkg, "..", "..", "skills", "worklog", "task-schema.json");

if (!fs.existsSync(SCHEMA)) {
  // Absent is not ok: with no schema this suite asserts nothing about drift.
  console.error(`schema-sync NOT RUN — nothing was asserted. The task schema is missing at ${SCHEMA}. Set WORKLOG_TASK_SCHEMA.`);
  process.exit(2);
}
const schema = JSON.parse(fs.readFileSync(SCHEMA, "utf8"));

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m) => { console.log(`  FAIL  ${m}`); fail++; };

const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "wmm-schema-")));
const bin = path.join(scratch, "bin");
fs.mkdirSync(bin, { recursive: true });
fs.writeFileSync(path.join(bin, "_lib.sh"), 'resolve_ldap() { echo "probe"; }\n');
const vault = path.join(scratch, "vault");
fs.mkdirSync(vault, { recursive: true });

const tools = await new Promise((resolve, reject) => {
  const child = spawn("node", [SERVER], {
    env: { ...process.env, WORKLOG_REPO: vault, WORKLOG_BIN: bin },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let err = "", buf = "";
  child.stderr.on("data", (c) => { err += c; });
  child.on("exit", (code) => reject(new Error(`server exited with ${code}\n${err}`)));
  child.stdout.on("data", (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.id === 2) { child.kill(); resolve(msg.result.tools); }
      } catch { /* not JSON */ }
    }
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "schema-sync", version: "0" } } }) + "\n");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" }) + "\n");
  setTimeout(() => { child.kill(); reject(new Error(`timeout\n${err}`)); }, 30000);
});

const byName = Object.fromEntries(tools.map((t) => [t.name, t]));
const enumOf = (tool, prop) => byName[tool]?.inputSchema?.properties?.[prop]?.enum;

// --- kinds ---
const mcpKinds = enumOf("memory_task_create", "kind");
if (!mcpKinds) {
  bad("memory_task_create exposes no kind enum to compare");
} else {
  const missing = schema.kinds.filter((k) => !mcpKinds.includes(k));
  const extra = mcpKinds.filter((k) => !schema.kinds.includes(k));
  if (missing.length === 0 && extra.length === 0) {
    ok(`memory_task_create offers exactly the schema's ${schema.kinds.length} kinds`);
  } else {
    bad(`kind drift — unreachable through the MCP: ${missing.join(", ") || "none"}; offered but not valid: ${extra.join(", ") || "none"}`);
  }
}

// --- statuses an agent may set ---
const mcpStatuses = enumOf("memory_checkpoint", "status");
const writable = schema.statuses.agent_writable;
if (!mcpStatuses) {
  bad("memory_checkpoint exposes no status enum to compare");
} else {
  const missing = writable.filter((s) => !mcpStatuses.includes(s));
  const extra = mcpStatuses.filter((s) => !writable.includes(s));
  if (missing.length === 0 && extra.length === 0) {
    ok(`memory_checkpoint offers exactly the schema's ${writable.length} agent-writable statuses`);
  } else {
    bad(`status drift — missing: ${missing.join(", ") || "none"}; offered but not agent-writable: ${extra.join(", ") || "none"}`);
  }
}

// --- the two sets must stay distinct, and for a stated reason ---
const excluded = Object.keys(schema.statuses.excluded_from_agent_writable || {});
const derived = schema.statuses.valid.filter((s) => !writable.includes(s));
if (derived.length > 0 && derived.every((s) => excluded.includes(s))) {
  ok(`every valid status withheld from agents is excluded for a stated reason (${derived.join(", ")})`);
} else {
  bad(`valid minus agent_writable is [${derived.join(", ")}] but the schema states reasons for [${excluded.join(", ")}] — an exclusion without a reason, or a merged list that certifies nothing`);
}

// archived must never be settable through the ordinary write path.
if (mcpStatuses && !mcpStatuses.includes("archived")) {
  ok("memory_checkpoint cannot set archived; the terminal transition stays with the archive path");
} else if (mcpStatuses) {
  bad("memory_checkpoint offers archived — setting the frontmatter alone leaves the file in active/");
}

fs.rmSync(scratch, { recursive: true, force: true });
console.log(`schema-sync: ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
