#!/usr/bin/env node
// Start the installed entry exactly as a desktop client would, without a shell.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const config = JSON.parse(fs.readFileSync(path.join(os.homedir(), ".cursor/mcp.json"), "utf8"));
const entries = Object.entries(config.mcpServers).filter(([name]) => name.startsWith("worklog-"));
assert.equal(entries.length, 1);
const [, entry] = entries[0];
const client = new Client({ name: "configured-dogfood", version: "1" });
const transport = new StdioClientTransport({ ...entry, env: { ...entry.env, HOME: os.homedir() }, stderr: "pipe" });
let diagnostic = "";
transport.stderr?.on("data", chunk => { diagnostic += chunk; });
try {
  await client.connect(transport);
  const tools = await client.listTools();
  assert.ok(tools.tools.some(t => t.name === "memory_claim"));
  const projects = await client.callTool({ name: "memory_projects", arguments: {} });
  assert.equal(projects.isError, false, JSON.stringify(projects.content));
  console.log("  PASS  installed client entry starts from a desktop-style environment and reads its vault");
} catch (error) {
  throw new Error(`${error.message}\n${diagnostic}`, { cause: error });
} finally {
  await client.close();
}
