#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { boardControl } from "./board.js";

const helpers = path.resolve(import.meta.dirname, "../../skills/worklog/bin");
let repo = process.env.WORKLOG_REPO, action = "open", open = true, json = false, port;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case "--repo": repo = args[++i]; break;
    case "--no-open": open = false; break;
    case "--json": json = true; break;
    case "--status": action = "status"; open = false; break;
    case "--stop": action = "stop"; open = false; break;
    case "--restart": action = "restart"; break;
    case "--port": port = Number(args[++i]); break;
    case "--help": case "-h":
      console.log("worklog-board [--repo PATH] [--no-open] [--status|--stop|--restart] [--port N] [--json]"); process.exit(0); break;
    default: throw new Error(`Unknown argument: ${args[i]}`);
  }
}
if (!repo) {
  const output = execFileSync("bash", [path.join(helpers, "bootstrap.sh"), "probe"], { encoding: "utf8" });
  const vaults = output.split("\n").filter(l => l.startsWith("vault\t")).map(l => l.split("\t")[1]);
  const matching = vaults.filter(v => process.cwd().startsWith(path.dirname(v) + path.sep) || process.cwd() === path.dirname(v)).sort((a, b) => b.length - a.length);
  repo = matching[0] || (vaults.length === 1 ? vaults[0] : null);
  if (!repo) throw new Error("Choose a vault: worklog-board --repo /path/to/_worklog");
}
repo = fs.realpathSync(repo);
if (!fs.existsSync(path.join(repo, "people")) || !fs.existsSync(path.join(repo, ".git"))) throw new Error("Not a Worklog vault");
if (port !== undefined && (!Number.isInteger(port) || port < 0 || port > 65535)) throw new Error("Invalid port");
if (action === "restart") await boardControl({ repo, action: "stop" });
const result = await boardControl({ repo, action: action === "restart" ? "open" : action, port });
console.log(json ? JSON.stringify(result) : result.url || "Board stopped.");
if (open && result.url) {
  const command = process.platform === "darwin" ? "open" : "xdg-open";
  const child = spawn(command, [result.url], { stdio: "ignore", detached: true });
  child.on("error", () => console.error(`Open ${result.url} in your browser.`));
  child.unref();
}
