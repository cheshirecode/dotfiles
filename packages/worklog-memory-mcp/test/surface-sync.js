#!/usr/bin/env node
// Keep this server and the worklog skill in step.
//
// The skill is the upstream: it grows modes and renames scripts on its own
// schedule. Nothing here can stop that, so the test makes drift LOUD instead.
// coverage.json classifies every public mode as either wrapped by named tools
// or exempt with a written reason, and this test checks the classification
// against reality in both directions:
//
//   registry.md -> coverage.json   a new mode is unclassified            FAIL
//   coverage.json -> registry.md   a mode was removed or renamed         FAIL
//   coverage.json -> tools/list    a named tool does not exist           FAIL
//   tools/list -> coverage.json    a tool nothing accounts for           FAIL
//
// An exemption must name one literal mode. A glob or a prefix would exempt
// whatever the skill adds next, which is the failure this file exists to stop.

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const here = import.meta.dirname;
const pkg = path.join(here, "..");
const coverage = JSON.parse(fs.readFileSync(path.join(pkg, "coverage.json"), "utf8"));
const registryPath = process.env.WORKLOG_MODE_REGISTRY || path.join(pkg, coverage.registry);

if (!fs.existsSync(registryPath)) {
  // Absent is not ok. Without the registry this suite asserts nothing about
  // drift, and a green run would read as proof that nothing drifted.
  console.error(`surface-sync NOT RUN — nothing was asserted. The mode registry is missing at ${registryPath}. Set WORKLOG_MODE_REGISTRY to the worklog skill's modes/registry.md.`);
  process.exit(2);
}

let pass = 0, fail = 0;
const ok = (m) => { console.log(`  PASS  ${m}`); pass++; };
const bad = (m) => { console.log(`  FAIL  ${m}`); fail++; };

// --- the skill's own list, between the markers codex-surface-check.sh uses ---
const raw = fs.readFileSync(registryPath, "utf8");
const block = raw.split("<!-- MODE_REGISTRY_BEGIN -->")[1]?.split("<!-- MODE_REGISTRY_END -->")[0];
if (!block) {
  console.error(`surface-sync NOT RUN — ${registryPath} has no MODE_REGISTRY markers, so the mode list could not be read.`);
  process.exit(2);
}
const modes = block.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- ")).map((l) => l.slice(2).trim());
if (modes.length === 0) {
  console.error(`surface-sync NOT RUN — the registry block in ${registryPath} is empty.`);
  process.exit(2);
}

const classified = new Set(Object.keys(coverage.modes));

const unclassified = modes.filter((m) => !classified.has(m));
if (unclassified.length === 0) ok(`every one of the ${modes.length} public modes is classified`);
else bad(`the skill has modes coverage.json does not classify: ${unclassified.join(", ")} — wrap each in a tool or exempt it by name with a reason`);

const stale = [...classified].filter((m) => !modes.includes(m));
if (stale.length === 0) ok("coverage.json names no mode the skill has dropped");
else bad(`coverage.json still classifies: ${stale.join(", ")} — the skill no longer lists them`);

// Each entry is exactly one of covered or exempt, and an exemption states why.
const malformed = Object.entries(coverage.modes).filter(([, v]) => {
  const covered = Array.isArray(v.tools) && v.tools.length > 0;
  const exempt = typeof v.exempt === "string" && v.exempt.trim().length > 20;
  return covered === exempt; // neither, or both
});
if (malformed.length === 0) ok("each mode is either wrapped by named tools or exempt with a stated reason");
else bad(`entries that are neither or both: ${malformed.map(([k]) => k).join(", ")}`);

// --- the server's live surface -----------------------------------------------
// A probe bin/ and an empty vault: the tool list does not depend on vault data.
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "wmm-surface-")));
const bin = path.join(scratch, "bin");
fs.mkdirSync(bin, { recursive: true });
fs.writeFileSync(path.join(bin, "_lib.sh"), 'resolve_ldap() { echo "probe"; }\n');
const vault = path.join(scratch, "vault");
fs.mkdirSync(vault, { recursive: true });

const listed = await new Promise((resolve, reject) => {
  const child = spawn("node", [path.join(pkg, "server.js")], {
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
        if (msg.id === 2) { child.kill(); resolve(msg.result.tools.map((t) => t.name)); }
      } catch { /* not JSON */ }
    }
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "surface-sync", version: "0" } } }) + "\n");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" }) + "\n");
  setTimeout(() => { child.kill(); reject(new Error(`timeout listing tools\n${err}`)); }, 30000);
});

const named = new Set(Object.values(coverage.modes).flatMap((v) => v.tools || []));
for (const t of Object.keys(coverage.extra_tools || {})) named.add(t);

const missing = [...named].filter((t) => !listed.includes(t));
if (missing.length === 0) ok(`every tool coverage.json names exists (${listed.length} live tools)`);
else bad(`coverage.json names tools the server does not serve: ${missing.join(", ")}`);

const orphans = listed.filter((t) => !named.has(t));
if (orphans.length === 0) ok("every live tool is accounted for by a mode or listed in extra_tools");
else bad(`the server serves tools nothing accounts for: ${orphans.join(", ")} — map each to a mode or explain it in extra_tools`);

// --- flag drift ---------------------------------------------------------
// A renamed flag is the drift the name checks cannot see: the tool keeps
// building its argv right up to the moment the script rejects it, and the
// failure surfaces as a runtime error in someone's session, not here.
const BIN = process.env.WORKLOG_BIN || path.join(pkg, "..", "..", "skills", "worklog", "bin");
const contracts = Object.entries(coverage.contracts || {});
if (contracts.length === 0) {
  bad("coverage.json declares no contracts — flag drift is unchecked");
} else if (!fs.existsSync(BIN)) {
  // Absent, not ok: without the scripts nothing about flags was asserted.
  console.error(`surface-sync: flag drift NOT CHECKED — the worklog bin/ is missing at ${BIN}. Set WORKLOG_BIN.`);
  fs.rmSync(scratch, { recursive: true, force: true });
  console.log(`surface-sync: ${pass} pass, ${fail} fail (flag drift not checked)`);
  process.exit(fail ? 1 : 2);
} else {
  const { execFileSync } = await import("node:child_process");
  const problems = [];
  for (const [tool, c] of contracts) {
    const script = path.join(BIN, c.script);
    if (!fs.existsSync(script)) { problems.push(`${tool}: ${c.script} is gone`); continue; }
    let help = "";
    try {
      help = execFileSync("bash", [script, "--help"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    } catch (err) {
      // A script that cannot print help is broken, not compliant.
      help = `${err.stdout || ""}${err.stderr || ""}`;
      if (!help.trim()) { problems.push(`${tool}: ${c.script} --help produced nothing`); continue; }
    }
    const gone = (c.flags || []).filter((f) => !help.includes(f));
    if (gone.length) problems.push(`${tool} -> ${c.script}: ${gone.join(", ")}`);
  }
  if (problems.length === 0) ok(`every flag ${contracts.length} tools pass still appears in its script's --help`);
  else bad(`flags the scripts no longer advertise:\n      ${problems.join("\n      ")}`);
}

// Every live tool needs a contract, or its script can be renamed unnoticed.
const uncontracted = listed.filter((t) => !(coverage.contracts || {})[t]);
if (uncontracted.length === 0) ok("every live tool pins the script and flags it depends on");
else bad(`tools with no contract entry: ${uncontracted.join(", ")}`);

fs.rmSync(scratch, { recursive: true, force: true });
console.log(`surface-sync: ${pass} pass, ${fail} fail`);
process.exit(fail ? 1 : 0);
