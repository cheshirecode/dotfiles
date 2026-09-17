#!/usr/bin/env node
// A tool result must carry BOTH streams of the script it wrapped.
//
// Why this test exists: run() returned `stdout || stderr`, so stderr was
// discarded whenever the script also wrote to stdout. checkpoint.sh prints
// "lint SKIPPED" and "lint ERROR" to stderr (lines 223 and 227), and a
// successful checkpoint always prints "pushed <slug>" to stdout. Every
// memory_checkpoint and memory_task_create result therefore dropped the lint
// outcome, and a lint that never ran looked exactly like a clean one — the
// absent-vs-ok collapse, inside the tool.
//
// The probe is a fake bin/ whose checkpoint.sh writes a known line to each
// stream. No vault and no network.

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const SERVER = process.env.WMM_SERVER || path.join(import.meta.dirname, "..", "server.js");
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "wmm-streams-")));

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m) => { console.log(`  FAIL  ${m}`); fail++; };

const OUT_LINE = "checkpoint: pushed probe-slug";
const ERR_LINE = "checkpoint: lint SKIPPED - probe detail";

const bin = path.join(scratch, "bin");
fs.mkdirSync(bin, { recursive: true });
fs.writeFileSync(path.join(bin, "_lib.sh"), 'resolve_ldap() { echo "probe"; }\n');
// Both streams, stdout non-empty — the exact shape of a successful checkpoint
// whose lint had something to say.
fs.writeFileSync(
  path.join(bin, "checkpoint.sh"),
  `#!/usr/bin/env bash\necho "${ERR_LINE}" >&2\necho "${OUT_LINE}"\n`
);
fs.chmodSync(path.join(bin, "checkpoint.sh"), 0o755);

const vault = path.join(scratch, "vault");
fs.mkdirSync(vault, { recursive: true });

const result = await new Promise((resolve, reject) => {
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
        if (msg.id === 2) { child.kill(); resolve(msg.result); }
      } catch { /* not JSON */ }
    }
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "streams", version: "0" } } }) + "\n");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  child.stdin.write(JSON.stringify({
    jsonrpc: "2.0", id: 2, method: "tools/call",
    params: { name: "memory_task_create", arguments: {
      slug: "probe-slug", kind: "spike", context: "stream probe", next_action: "assert both streams",
    } },
  }) + "\n");
  setTimeout(() => { child.kill(); reject(new Error(`timeout\n${err}`)); }, 30000);
});

const out = result?.content?.[0]?.text || "";

if (out.includes(OUT_LINE)) ok("the tool result carries the script's stdout");
else bad(`stdout missing from the tool result: ${out.slice(0, 200)}`);

// The one that regressed. stdout is non-empty here, which is exactly when
// `stdout || stderr` threw stderr away.
if (out.includes(ERR_LINE)) ok("the tool result carries the script's stderr even when stdout is non-empty");
else bad(`stderr was dropped while stdout was non-empty — a lint that never ran reads as clean. Got: ${out.slice(0, 200)}`);

fs.rmSync(scratch, { recursive: true, force: true });
console.log(`tool-output: ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
