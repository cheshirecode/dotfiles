#!/usr/bin/env node
// A semantic search that returns nothing must say WHY.
//
// A grep finding nothing means nothing matched. A semantic search finding
// nothing can equally mean the index was never built, is stale, or that
// fastembed is not importable from this server's scrubbed child environment.
// Collapsing those into "no results" is the absent-vs-ok defect in the one
// tool where the caller cannot see the cause — they get an empty answer and
// conclude the vault has nothing to say.
//
// Probe bin/: a fake search.sh emits each failure mode on demand, so all four
// states are reachable without building or breaking a real index.

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const SERVER = process.env.WMM_SERVER || path.join(import.meta.dirname, "..", "server.js");
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "wmm-sem-")));

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m) => { console.log(`  FAIL  ${m}`); fail++; };

const bin = path.join(scratch, "bin");
fs.mkdirSync(bin, { recursive: true });
fs.writeFileSync(path.join(bin, "_lib.sh"), 'resolve_ldap() { echo "probe"; }\n');
const vault = path.join(scratch, "vault");
fs.mkdirSync(vault, { recursive: true });

// $PROBE_MODE picks which failure the fake search.sh reproduces.
fs.writeFileSync(path.join(bin, "search.sh"), `#!/usr/bin/env bash
case "\${PROBE_MODE:-ok}" in
  ok)       echo "0.71  some-slug  people/probe/active/some-slug.md"; exit 0 ;;
  stale)    echo "0.71  some-slug  people/probe/active/some-slug.md"
            echo "search.sh: warning: semantic cache stale (3 missing, 1 older than source); run bin/embed.sh --refresh" >&2
            exit 0 ;;
  absent)   echo "search.sh: .cache/index.embeddings.jsonl missing — run bin/embed.sh first" >&2; exit 1 ;;
  broken)   echo "search.sh: warning: embedding cache is unreadable; run bin/embed.sh --refresh" >&2; exit 0 ;;
  nomodule) echo "ModuleNotFoundError: No module named 'fastembed'" >&2; exit 1 ;;
  weird)    echo "something nobody anticipated" >&2; exit 7 ;;
esac
`);
fs.chmodSync(path.join(bin, "search.sh"), 0o755);

function session(env) {
  const child = spawn("node", [SERVER], {
    env: { ...process.env, WORKLOG_REPO: vault, WORKLOG_BIN: bin, ...env },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let err = "", buf = "";
  const pend = new Map();
  child.stderr.on("data", (c) => { err += c; });
  child.on("exit", (code) => { for (const [, r] of pend) r({ __exit: code }); pend.clear(); });
  child.stdout.on("data", (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1);
      if (!l.trim()) continue;
      try { const m = JSON.parse(l); if (pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } } catch {}
    }
  });
  let id = 1;
  const req = (method, params) => new Promise((res, rej) => {
    const n = id++; pend.set(n, res);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: n, method, params }) + "\n");
    setTimeout(() => { if (pend.has(n)) { pend.delete(n); rej(new Error(`timeout ${method}\n${err}`)); } }, 30000);
  });
  return { req, close: () => child.kill() };
}

async function search(mode, args) {
  const s = session({ PROBE_MODE: mode });
  await s.req("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "sem", version: "0" } });
  const r = await s.req("tools/call", { name: "memory_search", arguments: args });
  s.close();
  return r.result?.content?.[0]?.text || "";
}

// Each failure mode must be NAMED, and must not read as "no results".
const cases = [
  ["ok",       "index: ",        false, "a healthy index adds no state banner"],
  ["stale",    "index: STALE",   true,  "a stale index says STALE, not zero results"],
  ["absent",   "index: ABSENT",  true,  "a missing index says ABSENT and that the search did not run"],
  ["broken",   "index: BROKEN",  true,  "an unreadable cache says BROKEN"],
  ["nomodule", "index: ABSENT",  true,  "fastembed not importable reports ABSENT, never ok"],
  ["weird",    "index: UNKNOWN", true,  "an unclassified non-zero exit reports UNKNOWN, not empty"],
];

for (const [mode, marker, want, label] of cases) {
  const out = await search(mode, { pattern: "q", semantic: true });
  const has = out.includes(marker);
  if (has === want) ok(label);
  else bad(`${label} — got: ${out.replace(/\n/g, " ").slice(0, 150)}`);
}

// The grep path must be untouched: no banner, no semantic flag passed.
const plain = await search("ok", { pattern: "q" });
if (!plain.includes("index:")) ok("the default grep path is unchanged and adds no banner");
else bad(`grep path gained a banner: ${plain.slice(0, 120)}`);

fs.rmSync(scratch, { recursive: true, force: true });
console.log(`semantic-states: ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
