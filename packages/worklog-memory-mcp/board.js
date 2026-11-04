// One local board per vault. All mutations use the same handlers as MCP.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import http from "node:http";
import { createHash, randomBytes } from "node:crypto";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);
const here = import.meta.dirname;
const version = "0.3.0";
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function location(repo, env) {
  const key = createHash("sha256").update(repo).digest("hex").slice(0, 12);
  const dir = path.join(env.XDG_CACHE_HOME || path.join(env.HOME || os.homedir(), ".cache"), "worklog-mcp");
  return { file: path.join(dir, `board-${key}.json`), log: path.join(dir, `board-${key}.log`),
    port: 18000 + parseInt(key.slice(0, 4), 16) % 20000 };
}
async function running(repo, env) {
  const { file } = location(repo, env);
  try {
    const state = JSON.parse(fs.readFileSync(file, "utf8"));
    if (state.repo !== repo || !Number.isInteger(state.port) || state.port < 1 || state.port > 65535) return null;
    const response = await fetch(`http://127.0.0.1:${state.port}/api/health`, { signal: AbortSignal.timeout(1000) });
    const health = await response.json();
    return health.repo === repo && health.instance === state.instance && health.pid === state.pid ? state : null;
  } catch { return null; }
}

export async function boardControl({ repo, env = process.env, action = "open", port }) {
  const existing = await running(repo, env);
  if (action === "status") return existing ? { running: true, ...existing } : { running: false, repo };
  if (existing && (action === "stop" || existing.version !== version)) {
    process.kill(existing.pid, "SIGTERM");
    for (let i = 0; i < 30 && await running(repo, env); i++) await delay(100);
  } else if (existing) return { running: true, ...existing };
  if (action === "stop") return { running: false, repo };
  const target = location(repo, env);
  fs.mkdirSync(path.dirname(target.file), { recursive: true, mode: 0o700 });
  const log = fs.openSync(target.log, "a", 0o600);
  const child = spawn(process.execPath, [path.join(here, "server.js"), "--board-server", "--board-port", String(port ?? target.port)], {
    env: { ...env, WORKLOG_REPO: repo }, cwd: repo, detached: true, stdio: ["ignore", log, log],
  });
  child.unref();
  fs.closeSync(log);
  for (let i = 0; i < 150; i++) {
    await delay(100);
    const state = await running(repo, env);
    if (state) return { running: true, ...state };
  }
  throw new Error(`Board did not start. Read ${target.log}; the chosen port may already be in use.`);
}

export async function serveBoard({ repo, ldap, bin, env, port, invoke }) {
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error("Invalid board port");
  const instance = randomBytes(20).toString("hex");
  const token = randomBytes(24).toString("hex");
  const target = location(repo, env);
  let state, cache, cacheAt = 0, loading;
  async function cards() {
    if (cache && Date.now() - cacheAt < 1500) return cache;
    if (!loading) loading = exec("python3", [path.join(here, "board-state.py"), repo, ldap, bin], {
      cwd: repo, env, maxBuffer: 16 * 1024 * 1024, timeout: 20000,
    }).then(({ stdout }) => { cache = JSON.parse(stdout); cacheAt = Date.now(); return cache; }).finally(() => { loading = null; });
    return loading;
  }
  const reply = (res, code, value, type = "application/json") => {
    res.writeHead(code, { "Content-Type": `${type}; charset=utf-8`, "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff", "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" });
    res.end(type === "application/json" ? JSON.stringify(value) : value);
  };
  const allowedTools = new Set(["memory_update_status", "memory_task_create"]);
  const server = http.createServer(async (req, res) => {
    const ownOrigin = `http://127.0.0.1:${state?.port}`;
    if (req.headers.host !== `127.0.0.1:${state?.port}` && req.headers.host !== `localhost:${state?.port}`) {
      reply(res, 403, { error: "Use the board's local URL." }); return;
    }
    try {
      const url = new URL(req.url, ownOrigin);
      if (req.method === "GET" && url.pathname === "/api/health") { reply(res, 200, state); return; }
      if (req.method === "GET" && url.pathname === "/api/state") {
        const data = await cards();
        reply(res, 200, { ...data, tasks: data.tasks.map(({ body, ...task }) => task), token,
          vault: path.basename(path.dirname(repo)), namespace: ldap, version }); return;
      }
      if (req.method === "GET" && url.pathname === "/api/task") {
        const data = await cards();
        const task = data.tasks.find(t => t.slug === url.searchParams.get("slug"));
        reply(res, task ? 200 : 404, task || { error: "Task not found." }); return;
      }
      if (req.method === "POST" && url.pathname === "/api/tool") {
        const origin = req.headers.origin;
        if ((origin && origin !== ownOrigin && origin !== `http://localhost:${state.port}`)
            || req.headers["x-worklog-token"] !== token || !req.headers["content-type"]?.startsWith("application/json")) {
          reply(res, 403, { error: "Refresh this local board and try again." }); return;
        }
        let body = "";
        for await (const chunk of req) {
          body += chunk;
          if (Buffer.byteLength(body) > 128000) { reply(res, 413, { error: "Task update is too large." }); return; }
        }
        const input = JSON.parse(body);
        if (!allowedTools.has(input.name)) { reply(res, 400, { error: "Unsupported board action." }); return; }
        const result = await invoke(input.name, input.arguments);
        cache = null;
        reply(res, result.isError ? 409 : 200, result); return;
      }
      const files = { "/": ["board.html", "text/html"], "/board.css": ["board.css", "text/css"], "/board-ui.js": ["board-ui.js", "text/javascript"] };
      if (req.method === "GET" && files[url.pathname]) {
        const [file, type] = files[url.pathname];
        reply(res, 200, fs.readFileSync(path.join(here, "web", file), "utf8"), type); return;
      }
      reply(res, 404, { error: "Not found." });
    } catch (error) { reply(res, 400, { error: error.message }); }
  });
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(port, "127.0.0.1", resolve); });
  const actualPort = server.address().port;
  state = { repo, pid: process.pid, port: actualPort, instance, version, url: `http://127.0.0.1:${actualPort}` };
  fs.mkdirSync(path.dirname(target.file), { recursive: true, mode: 0o700 });
  fs.writeFileSync(`${target.file}.${process.pid}`, JSON.stringify(state), { mode: 0o600 });
  fs.renameSync(`${target.file}.${process.pid}`, target.file);
  function cleanup() {
    try { if (JSON.parse(fs.readFileSync(target.file, "utf8")).instance === instance) fs.unlinkSync(target.file); } catch { /* already removed */ }
  }
  process.on("SIGTERM", () => { server.close(() => { cleanup(); process.exit(0); }); server.closeAllConnections(); });
  process.on("exit", cleanup);
  console.error(`Worklog board: ${state.url}`);
  return state;
}
