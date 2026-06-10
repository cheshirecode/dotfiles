import { parseArgs, usage, loadConfig } from "./config.mjs";
import { extractGraph } from "./extract.mjs";
import { renderDot, renderHtml, writeOutput } from "./render.mjs";

function runGraph(config) {
  const graph = extractGraph(config);

  if (config.format === "json") {
    writeOutput(`${JSON.stringify(graph, null, 2)}\n`, config.output);
  } else if (config.format === "dot") {
    writeOutput(renderDot(graph), config.output);
  } else if (config.format === "html") {
    writeOutput(renderHtml(graph), config.output);
  } else {
    throw new Error(`Unknown format: ${config.format}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage(process.env.WORKLOG_MANAGER_USAGE || "worklog-manager"));
    return;
  }
  const config = loadConfig(args);

  if (args.command === "graph") {
    runGraph(config);
  } else {
    throw new Error(`Unknown command: ${args.command}`);
  }
}

try {
  main();
} catch (error) {
  console.error(`worklog-manager: ${error.message}`);
  process.exit(1);
}
