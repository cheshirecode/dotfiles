import { parseArgs, usage, loadConfig } from "./config.mjs";
import { createDispatch, writeDispatchArtifacts } from "./dispatch.mjs";
import { extractGraph } from "./extract.mjs";
import { fetchIssue } from "./github.mjs";
import { readIssue } from "./issue.mjs";
import { renderDot, renderHtml, writeOutput } from "./render.mjs";

export const POLL_RUN_SCHEMA_VERSION = "worklog.poll-run.v1";

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

function runDispatch(config) {
  if (!config.issue) {
    throw new Error("dispatch requires --issue=file");
  }
  const graph = extractGraph(config);
  const issue = readIssue(config.issue);
  const dispatch = createDispatch(config, graph, issue);
  const runDir = writeDispatchArtifacts(config, dispatch);
  writeOutput(`${JSON.stringify({ runDir, dispatch }, null, 2)}\n`, config.output);
}

function pollTarget(config, graph, issueUrl) {
  const fetched = fetchIssue(config, issueUrl);
  if (fetched.notModified) {
    return { notModified: true, target: fetched.target, cursor: fetched.cursor, issueUrl };
  }

  const dispatch = createDispatch(config, graph, fetched.issue);
  const runDir = writeDispatchArtifacts(config, dispatch);
  return {
    notModified: false,
    target: fetched.target,
    cursor: fetched.cursor,
    issueUrl,
    runDir,
    comment: null,
    dispatch,
  };
}

function summarizePollResults(results) {
  const summary = {
    targetCount: new Set(results.map((result) => result.issueUrl)).size,
    iterationCount: new Set(results.map((result) => result.iteration)).size,
    notModified: 0,
    planned: 0,
    refused: 0,
    comments: 0,
  };
  for (const result of results) {
    if (result.notModified) {
      summary.notModified += 1;
      continue;
    }
    summary[result.dispatch.state] = (summary[result.dispatch.state] || 0) + 1;
    if (result.comment) summary.comments += 1;
  }
  return summary;
}

function sleepSeconds(seconds) {
  const waitMs = Math.max(0, Number(seconds) * 1000);
  if (!waitMs) return;
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, waitMs);
}

function runPoll(config) {
  const issueUrls = config.poll.issueUrls;
  if (!issueUrls.length) {
    throw new Error("poll requires --issue-url=https://github.com/owner/repo/issues/N or poll.issueUrls in config");
  }
  if (!Number.isInteger(config.poll.iterations) || config.poll.iterations < 1) {
    throw new Error("poll requires --iterations to be a positive integer");
  }
  if (!Number.isFinite(config.poll.intervalSeconds) || config.poll.intervalSeconds < 0) {
    throw new Error("poll requires --interval-seconds to be zero or positive");
  }

  const graph = extractGraph(config);
  if (issueUrls.length === 1 && config.poll.iterations === 1) {
    writeOutput(`${JSON.stringify(pollTarget(config, graph, issueUrls[0]), null, 2)}\n`, config.output);
    return;
  }

  const results = [];
  for (let iteration = 1; iteration <= config.poll.iterations; iteration += 1) {
    for (const issueUrl of issueUrls) {
      results.push({ iteration, ...pollTarget(config, graph, issueUrl) });
    }
    if (iteration < config.poll.iterations) sleepSeconds(config.poll.intervalSeconds);
  }

  writeOutput(`${JSON.stringify({
    schemaVersion: POLL_RUN_SCHEMA_VERSION,
    instance: config.instance,
    loop: {
      iterations: config.poll.iterations,
      intervalSeconds: config.poll.intervalSeconds,
      targetCount: issueUrls.length,
    },
    summary: summarizePollResults(results),
    results,
  }, null, 2)}\n`, config.output);
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
  } else if (args.command === "dispatch") {
    runDispatch(config);
  } else if (args.command === "poll") {
    runPoll(config);
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
