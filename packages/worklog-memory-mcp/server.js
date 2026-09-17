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
// --- The task file's vocabulary ----------------------------------------------
//
// kinds and statuses used to be hardcoded here while bin/_lint.py kept its own
// copies. _lint.py accepted 19 kinds and this file offered 8, so 11 kinds valid
// in the vault could not be written through the MCP at all. Both sides now read
// one schema.
//
// Resolution order: an explicit override, then the skill next to WORKLOG_BIN,
// then the sibling skill in this checkout. The last one is what lets a test
// point WORKLOG_BIN at a probe directory without losing the real vocabulary.
const SCHEMA_CANDIDATES = [
  process.env.WORKLOG_TASK_SCHEMA,
  BIN && path.join(BIN, "..", "task-schema.json"),
  path.join(import.meta.dirname, "..", "..", "skills", "worklog", "task-schema.json"),
].filter(Boolean);
const SCHEMA_PATH = SCHEMA_CANDIDATES.find((p) => fs.existsSync(p));
if (!SCHEMA_PATH) {
  // Absent is not ok. Falling back to a private copy is how the drift started.
  console.error(`worklog-memory-mcp: no task schema found. Looked in:\n  ${SCHEMA_CANDIDATES.join("\n  ")}\nSet WORKLOG_TASK_SCHEMA.`);
  process.exit(78);
}
let SCHEMA;
try {
  SCHEMA = JSON.parse(fs.readFileSync(SCHEMA_PATH, "utf8"));
} catch (err) {
  console.error(`worklog-memory-mcp: task schema at ${SCHEMA_PATH} is unreadable: ${err.message}`);
  process.exit(78);
}
const KINDS = SCHEMA.kinds;
// What a tool may SET, which is not what may EXIST. `archived` is valid in a
// committed file but is withheld here: reaching it also moves the file from
// active/ to archive/, so writing the frontmatter alone is not the transition.
const AGENT_STATUSES = SCHEMA.statuses.agent_writable;
if (!Array.isArray(KINDS) || KINDS.length === 0 || !Array.isArray(AGENT_STATUSES) || AGENT_STATUSES.length === 0) {
  console.error(`worklog-memory-mcp: task schema at ${SCHEMA_PATH} has no kinds or no agent_writable statuses`);
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
    // Both streams, always. This was `stdout || stderr`, which threw stderr
    // away whenever the script also wrote to stdout — and a successful
    // checkpoint always does. checkpoint.sh prints "lint SKIPPED" and
    // "lint ERROR" to stderr, so the lint outcome never reached the caller
    // and a lint that never ran read exactly like a clean one.
    return { ok: true, out: [stdout.trim(), stderr.trim()].filter(Boolean).join("\n") };
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

// A task lives under active/ until it is archived, then under archive/.
// Anything that reads or edits an existing task must look in both.
function taskFile(slug) {
  for (const state of ["active", "archive"]) {
    const file = path.join(REPO, "people", LDAP, state, `${slug}.md`);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

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
    kind: z.enum([...KINDS]).default("plan"),
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
    status: z.enum([...AGENT_STATUSES]).optional(),
    next_action: z.string().optional(),
  },
  ({ slug, evidence, status, next_action }) =>
    serialized(async () => {
      const file = taskFile(slug);
      if (!file) {
        return text({ ok: false, out: `task ${slug} not found — use memory_task_create` });
      }
      if (file.includes(`${path.sep}archive${path.sep}`)) {
        return text({ ok: false, out: `task ${slug} is archived; archived tasks are a closed record` });
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

// --- Lifecycle, discovery and self-check -----------------------------------
//
// memory_task_create and memory_checkpoint can start and advance a task but
// never finish one: `archived` is the FSM's terminal state and archive.sh is
// the only thing that reaches it, because it also moves the file from active/
// to archive/. Setting the frontmatter alone would leave the task in the wrong
// directory. The three read tools below close the other half of the loop —
// without them a caller must already know a slug before it can do anything.

server.tool(
  "memory_archive",
  "Close a task: set status=archived, write a summary, and move it from active/ to archive/. This is the FSM's terminal transition and the only way to finish a task.",
  {
    slug: z.string().regex(SLUG),
    reason: z.enum(["shipped", "declined", "abandoned", "superseded", "merged", "obsolete"]).default("shipped"),
    summary: z.string().min(1).describe("2-3 lines, written into frontmatter so the archive stays browsable"),
    superseded_by: z.string().regex(SLUG).optional().describe("required shape for reason=superseded"),
    pr: z.string().optional(),
  },
  ({ slug, reason, summary, superseded_by, pr }) =>
    serialized(async () => {
      const file = taskFile(slug);
      if (!file) return text({ ok: false, out: `task ${slug} not found` });
      if (file.includes(`${path.sep}archive${path.sep}`)) {
        return text({ ok: false, out: `task ${slug} is already archived` });
      }
      // archive.sh only warns when a summary is missing, and the vault has
      // five archived tasks with none. An agent has no excuse, so require it.
      const why = reason === "superseded" && superseded_by ? `superseded by ${superseded_by}` : reason;
      const args = [slug, `--reason=${why}`, `--summary=${summary}`];
      if (pr) args.push(`--pr=${pr}`);
      return text(await run("archive.sh", args));
    })
);

server.tool(
  "memory_status",
  "What is in flight: recent task activity for this vault, without needing a slug first. Start here when resuming cold.",
  {
    since: z.string().optional().describe("git date, e.g. yesterday, 1.week.ago, 2026-04-15; default midnight today"),
    slug: z.string().regex(SLUG).optional(),
    project: z.string().optional(),
    format: z.enum(["markdown", "grouped", "json"]).default("markdown"),
    include_meta: z.boolean().default(false),
  },
  async ({ since, slug, project, format, include_meta }) => {
    const args = [`--format=${format}`];
    if (since) args.push(`--since=${since}`);
    if (slug) args.push(`--slug=${slug}`);
    if (project) args.push(`--project=${project}`);
    if (include_meta) args.push("--include-meta");
    return text(await run("status.sh", args));
  }
);

server.tool(
  "memory_related",
  "Prior-art probe across active and archive task bodies, or the list of project slugs already in use. Run BEFORE memory_task_create so a decision is not re-made under a new slug.",
  {
    keywords: z.array(z.string().min(1)).min(1).optional(),
    projects: z.boolean().default(false).describe("list project: slugs in use instead of searching"),
  },
  async ({ keywords, projects }) => {
    if (projects) return text(await run("related-search.sh", ["--projects"]));
    if (!keywords?.length) {
      return text({ ok: false, out: "pass keywords, or projects=true to enumerate project slugs" });
    }
    return text(await run("related-search.sh", keywords));
  }
);

server.tool(
  "memory_lint",
  "Check task files against the vault's own rules. memory_checkpoint already lints what it commits; use this to inspect a task without writing, or to sweep the vault.",
  {
    slug: z.string().regex(SLUG).optional().describe("omit to lint every task file"),
    cross_task: z.boolean().default(false).describe("include active-task drift checks"),
    format: z.enum(["markdown", "json"]).default("markdown"),
  },
  async ({ slug, cross_task, format }) => {
    const args = [`--format=${format}`];
    if (slug) {
      const file = taskFile(slug);
      if (!file) return text({ ok: false, out: `task ${slug} not found` });
      args.push(`--file=${path.relative(REPO, file)}`);
    }
    if (cross_task) args.push("--cross-task");
    return text(await run("lint.sh", args));
  }
);

await resolveVaultEnv();
LDAP = await resolveLdap();

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`worklog-memory-mcp: serving vault ${REPO} as ${LDAP} (env: ${ENV_MODE})`);
