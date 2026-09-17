#!/usr/bin/env node
// worklog-memory-mcp: MCP agent-memory server over a git worklog vault.
//
// Differentiator vs generic memory servers: memories are task FILES with an
// FSM (draft -> in-progress -> ... -> archived), typed evidence lines, and
// git history — durable, lintable, human-readable. This server wraps the
// worklog skill's own scripts, so every write passes the vault's lint and
// commit hooks; it invents no second rule surface.
//
// Env:
//   WORKLOG_REPO  path to the vault clone (required)
//   WORKLOG_BIN   path to the worklog skill's bin/ (required)
//   WORKLOG_LDAP  namespace under people/ (default: from vault convention)
//
// Concurrency: the vault's own lock (_flock.py) is a single coarse lock and
// the git index is not multi-writer; this server therefore serializes all
// write tools through one in-process queue. Run one server per vault.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const exec = promisify(execFile);

// direnv keys its allow store by the CANONICAL path, so a vault reached
// through a symlink (on macOS /var/... for /private/var/...) reads as blocked
// even after `direnv allow`. Resolve once, up front, and use that everywhere.
const RAW_REPO = process.env.WORKLOG_REPO;
const REPO = RAW_REPO && fs.existsSync(RAW_REPO) ? fs.realpathSync(RAW_REPO) : RAW_REPO;
// This package lives inside the dotfiles repo, next to the worklog skill:
// default WORKLOG_BIN to the sibling skill so a dotfiles checkout is
// self-contained; the env var still overrides for installed-skill layouts.
const DEFAULT_BIN = path.join(import.meta.dirname, "..", "..", "skills", "worklog", "bin");
const BIN = process.env.WORKLOG_BIN || (fs.existsSync(DEFAULT_BIN) ? DEFAULT_BIN : "");
if (!REPO || !BIN) {
  console.error("worklog-memory-mcp: WORKLOG_REPO is required (WORKLOG_BIN defaults to the sibling worklog skill)");
  process.exit(78);
}
if (!fs.existsSync(REPO)) {
  console.error(`worklog-memory-mcp: WORKLOG_REPO does not exist: ${RAW_REPO}`);
  process.exit(78);
}
// --- Vault-scoped child environment -----------------------------------------
//
// The launching shell is usually a DIFFERENT vault's direnv scope. A session
// started in the dotfiles checkout exports the oss identity: GIT_AUTHOR_NAME,
// GH_TOKEN, NPM_TOKEN, WORKLOG_LDAP=oss. Forwarding process.env to a work
// vault write commits under the wrong author with the wrong token, and the
// work vault's own `unset GH_TOKEN` / `unset WORKLOG_LDAP` never run, because
// the scripts are invoked directly instead of through direnv.
//
// So: drop every family that carries identity, namespace or credentials, then
// let the VAULT's own .envrc chain repopulate them. DIRENV_ is dropped too, so
// resolution does not depend on the caller's direnv state; an app launched
// from Finder has none, and then direnv would unload nothing.
const SCRUB = /^(WORKLOG_|GIT_AUTHOR_|GIT_COMMITTER_|GIT_USER_|GIT_CONFIG|GH_|GITHUB_|NPM_|NODE_AUTH_|DIRENV_)/;

function scrubbedBase() {
  const base = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!SCRUB.test(k)) base[k] = v;
  }
  base.DIRENV_LOG_FORMAT = ""; // keep direnv progress lines out of tool results
  return base;
}

// Four states, never collapsed to two. A vault whose .envrc exists but cannot
// be loaded is BLOCKED, not "fine without it": that is exactly the case where
// the identity config is present and we would otherwise ignore it in silence.
let ENV_MODE = "unknown";
let CHILD_ENV = scrubbedBase();

async function resolveVaultEnv() {
  const hasEnvrc = fs.existsSync(path.join(REPO, ".envrc"));
  let direnv = true;
  try {
    await exec("direnv", ["version"], { env: CHILD_ENV });
  } catch {
    direnv = false;
  }
  if (!direnv) {
    ENV_MODE = hasEnvrc ? "blocked:no-direnv" : "scrubbed:no-direnv";
  } else if (!hasEnvrc) {
    ENV_MODE = "scrubbed:no-envrc";
  } else {
    try {
      const { stdout } = await exec("direnv", ["exec", REPO, "env", "-0"], {
        cwd: REPO,
        env: CHILD_ENV,
        maxBuffer: 4 * 1024 * 1024,
      });
      const resolved = {};
      for (const entry of stdout.split("\0")) {
        const i = entry.indexOf("=");
        if (i > 0) resolved[entry.slice(0, i)] = entry.slice(i + 1);
      }
      CHILD_ENV = resolved;
      ENV_MODE = "direnv";
    } catch (err) {
      ENV_MODE = "blocked:direnv-failed";
      console.error(`worklog-memory-mcp: direnv could not load ${REPO}/.envrc — run 'direnv allow' in that directory.\n${err.stderr || err.message}`);
    }
  }
  if (ENV_MODE.startsWith("blocked")) {
    console.error(`worklog-memory-mcp: refusing to serve ${REPO} (${ENV_MODE}); its .envrc carries the vault identity and could not be applied.`);
    process.exit(78);
  }
  // This server's contract is "serve REPO", so REPO wins over any .envrc
  // value; every other variable comes from the vault.
  CHILD_ENV.WORKLOG_REPO = REPO;
  CHILD_ENV.DIRENV_LOG_FORMAT = "";
  // WORKLOG_LDAP used to default to "oss". That overrode the work vault's
  // deliberate `unset WORKLOG_LDAP` and — worse — switched off
  // verify_provenance in _lib.sh, whose namespace/email mismatch check runs
  // only when no explicit namespace is set.
  //
  // An MCP client merges its configured `env:` block into this process's
  // environment, so an ambient WORKLOG_LDAP leaked by the launching shell is
  // indistinguishable from one an operator configured. When the vault has its
  // own .envrc, that file is therefore the authority and the ambient value is
  // dropped. Only a vault with no .envrc of its own takes the process value,
  // because there is nothing else to read it from.
  if (ENV_MODE.startsWith("scrubbed") && process.env.WORKLOG_LDAP) {
    CHILD_ENV.WORKLOG_LDAP = process.env.WORKLOG_LDAP;
  }
}

// Ask the vault's own resolver, so the path this server writes to and the path
// its scripts commit always agree.
async function resolveLdap() {
  const { stdout } = await exec(
    "bash",
    ["-c", 'set -e; cd "$1"; . "$2/_lib.sh"; resolve_ldap', "_", REPO, BIN],
    { cwd: REPO, env: CHILD_ENV }
  );
  const ldap = stdout.trim();
  if (!ldap) throw new Error("resolve_ldap returned an empty namespace");
  return ldap;
}

let LDAP = "";

async function run(script, args, opts = {}) {
  try {
    const { stdout, stderr } = await exec("bash", [path.join(BIN, script), ...args], {
      cwd: REPO,
      env: CHILD_ENV,
      maxBuffer: 4 * 1024 * 1024,
      ...opts,
    });
    return { ok: true, out: stdout || stderr };
  } catch (err) {
    return { ok: false, out: `${err.stdout || ""}${err.stderr || err.message}` };
  }
}

function text(result) {
  return { content: [{ type: "text", text: result.out.trim() || "(empty)" }], isError: !result.ok };
}

// One in-process queue serializes every vault write.
let writeChain = Promise.resolve();
function serialized(fn) {
  const next = writeChain.then(fn, fn);
  writeChain = next.catch(() => {});
  return next;
}

const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

const server = new McpServer({ name: "worklog-memory", version: "0.1.0" });

server.tool(
  "memory_search",
  "Search the worklog vault (task bodies + frontmatter index). Returns slug-grouped hits.",
  { pattern: z.string().min(1) },
  async ({ pattern }) => text(await run("search.sh", [pattern]))
);

server.tool(
  "memory_context",
  "Hydrate resume context for a task slug: frontmatter, recent commits, open next steps.",
  { slug: z.string().regex(SLUG), for: z.enum(["resume", "review", "compact"]).default("resume") },
  async ({ slug, for: mode }) => text(await run("context.sh", [slug, `--for=${mode}`]))
);

server.tool(
  "memory_task_create",
  "Create a new task file (draft) in the vault and commit it. Body is markdown after the frontmatter.",
  {
    slug: z.string().regex(SLUG),
    kind: z.enum(["plan", "impl", "investigation", "design", "spike", "proposal", "bug", "tooling"]).default("plan"),
    context: z.string().min(1),
    next_action: z.string().min(1),
  },
  ({ slug, kind, context, next_action }) =>
    serialized(async () => {
      const file = path.join(REPO, "people", LDAP, "active", `${slug}.md`);
      if (fs.existsSync(file)) {
        return text({ ok: false, out: `task ${slug} already exists — use memory_checkpoint` });
      }
      const today = new Date().toISOString().slice(0, 10);
      const body = `---
slug: ${slug}
status: draft
kind: ${kind}
author: ${LDAP}
created: ${today}
last_updated: ${today}
project: none
next_action: "${next_action.replaceAll('"', "'")}"
---

## Context

${context}

## Next

- [ ] ${next_action}
`;
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, body);
      return text(await run("checkpoint.sh", [slug]));
    })
);

server.tool(
  "memory_checkpoint",
  "Record typed evidence ('kind: ref — result') on a task and commit. Optionally flip status or next_action.",
  {
    slug: z.string().regex(SLUG),
    evidence: z.string().min(1).describe("one typed line: command|artifact|git|github|url: <ref> — <result>"),
    status: z.enum(["draft", "in-progress", "in-review", "blocked", "shipping"]).optional(),
    next_action: z.string().optional(),
  },
  ({ slug, evidence, status, next_action }) =>
    serialized(async () => {
      const file = path.join(REPO, "people", LDAP, "active", `${slug}.md`);
      if (!fs.existsSync(file)) {
        return text({ ok: false, out: `task ${slug} not found — use memory_task_create` });
      }
      const today = new Date().toISOString().slice(0, 10);
      const note = `- ${today}: ${evidence}`;
      let content = fs.readFileSync(file, "utf8");
      // Append under an ## Evidence section, creating it once.
      if (content.includes("\n## Evidence\n")) {
        content = content.replace("\n## Evidence\n", `\n## Evidence\n${note}\n`);
      } else {
        content += `\n## Evidence\n${note}\n`;
      }
      fs.writeFileSync(file, content);
      const args = [slug];
      if (status) args.push(`--status=${status}`);
      if (next_action) args.push(`--next=${next_action}`);
      return text(await run("checkpoint.sh", args));
    })
);

await resolveVaultEnv();
LDAP = await resolveLdap();

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`worklog-memory-mcp: serving vault ${REPO} as ${LDAP} (env: ${ENV_MODE})`);
