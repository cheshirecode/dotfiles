import fs from "node:fs";
import path from "node:path";

export const INSTANCE_SCHEMA_VERSION = "worklog-manager.instance.v1";
const FORMATS = new Set(["json", "dot", "html"]);

export function parseArgs(argv) {
  const out = {
    config: "",
    format: "html",
    output: "",
    repo: "",
    instance: "",
    githubRepos: [],
    graphProjects: [],
    graphMatches: [],
    activeOnly: false,
    issue: "",
    expectedIssueHash: "",
    execute: false,
    help: false,
    command: "graph",
  };

  if (argv[0] && !argv[0].startsWith("-")) {
    out.command = argv[0];
    argv = argv.slice(1);
  } else {
    out.command = "graph";
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const readValue = (name) => {
      if (arg.startsWith(`${name}=`)) return arg.slice(name.length + 1);
      i += 1;
      if (argv[i] === undefined) throw new Error(`${name} requires a value`);
      return argv[i];
    };

    if (arg === "--active-only") out.activeOnly = true;
    else if (arg === "--config" || arg.startsWith("--config=")) out.config = readValue("--config");
    else if (arg === "--format" || arg.startsWith("--format=")) out.format = readValue("--format");
    else if (arg === "--output" || arg.startsWith("--output=")) out.output = readValue("--output");
    else if (arg === "-o") out.output = readValue("-o");
    else if (arg === "--repo" || arg.startsWith("--repo=")) out.repo = readValue("--repo");
    else if (arg === "--instance" || arg.startsWith("--instance=")) out.instance = readValue("--instance");
    else if (arg === "--github-repo" || arg.startsWith("--github-repo=")) out.githubRepos.push(readValue("--github-repo"));
    else if (arg === "--project" || arg.startsWith("--project=")) out.graphProjects.push(readValue("--project"));
    else if (arg === "--match" || arg.startsWith("--match=")) out.graphMatches.push(readValue("--match"));
    else if (arg === "--issue" || arg.startsWith("--issue=")) out.issue = readValue("--issue");
    else if (arg === "--expected-issue-hash" || arg.startsWith("--expected-issue-hash=")) out.expectedIssueHash = readValue("--expected-issue-hash");
    else if (arg === "--execute") out.execute = true;
    else if (arg === "--help" || arg === "-h") out.help = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return out;
}

export function usage(program = "node src/cli.js") {
  return [
    "usage:",
    `  ${program} graph [--config=file] [--repo=path] [--instance=name] [--github-repo=owner/repo] [--format=json|dot|html] [--output=file] [--active-only] [--project=slug] [--match=text]`,
    `  ${program} dispatch --config=file --issue=file [--expected-issue-hash=sha256] [--execute] [--output=file]`,
  ].join("\n");
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function uniqueSorted(values) {
  return [...new Set((values || []).filter(Boolean).map(String))].sort();
}

function uniqueInOrder(values) {
  const out = [];
  const seen = new Set();
  for (const value of (values || []).filter(Boolean).map(String)) {
    if (seen.has(value)) continue;
    seen.add(value);
    out.push(value);
  }
  return out;
}

function resolveMaybePath(cwd, value, fallback) {
  const raw = value || fallback;
  if (!raw) return "";
  return path.resolve(cwd, raw);
}

function normalizeGithub(config, args) {
  return {
    repos: uniqueSorted([
      ...(config.github?.repos || []),
      ...(config.githubRepos || []),
      ...args.githubRepos,
    ]),
  };
}

function normalizeSandbox(config) {
  const sandbox = config.sandbox || {};
  return {
    command: String(sandbox.command || ""),
    profile: String(sandbox.profile || ""),
    timeoutSeconds: Number(sandbox.timeoutSeconds || 900),
  };
}

function normalizeDaemon(config) {
  const daemon = config.daemon || {};
  const execution = daemon.execution || {};
  return {
    expectedLogin: String(daemon.expectedLogin || config.sandbox?.profile || ""),
    commands: uniqueSorted(daemon.commands || ["agent", "ask", "do", "plan"]),
    defaultSlug: String(daemon.defaultSlug || ""),
    statusCommentMarker: String(daemon.statusCommentMarker || "<!-- worklog-manager-status -->"),
    execution: {
      enabled: Boolean(execution.enabled || false),
      commands: uniqueSorted(execution.commands || ["agent"]),
      confirmation: String(execution.confirmation || "sandbox"),
    },
  };
}

export function loadConfig(args, cwd = process.cwd()) {
  let config = {};
  let configPath = "";
  if (args.config) {
    configPath = path.resolve(cwd, args.config);
    config = readJson(configPath);
  }

  const roots = config.roots || {};
  const worklogRepo = args.repo || roots.worklogRepo || config.worklogRepo || process.env.WORKLOG_REPO || cwd;
  const instance = args.instance || config.instance || path.basename(worklogRepo);
  const format = String(args.format || config.format || "html");
  if (!FORMATS.has(format)) {
    throw new Error(`Unknown format: ${format}`);
  }

  return {
    schemaVersion: config.schemaVersion || INSTANCE_SCHEMA_VERSION,
    configPath,
    instance,
    worklogRepo: path.resolve(cwd, worklogRepo),
    stateDir: resolveMaybePath(cwd, roots.stateDir || config.stateDir, path.join(".state", instance)),
    cacheDir: resolveMaybePath(cwd, roots.cacheDir || config.cacheDir, path.join(".cache", instance)),
    github: normalizeGithub(config, args),
    sandbox: normalizeSandbox(config),
    poll: {},
    daemon: normalizeDaemon(config),
    graphFilter: {
      projects: uniqueInOrder([
        ...(config.graphFilter?.projects || []),
        ...(config.projects || []),
        ...args.graphProjects,
      ]),
      matches: uniqueInOrder([
        ...(config.graphFilter?.matches || []),
        ...(config.matches || []),
        ...args.graphMatches,
      ]),
    },
    format,
    output: args.output ? path.resolve(cwd, args.output) : "",
    issue: args.issue ? path.resolve(cwd, args.issue) : "",
    expectedIssueHash: args.expectedIssueHash,
    execute: args.execute,
    activeOnly: Boolean(args.activeOnly || config.activeOnly || config.graphFilter?.activeOnly),
  };
}
