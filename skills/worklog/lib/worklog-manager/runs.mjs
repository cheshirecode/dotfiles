import { createDispatch, executeDispatch, writeDispatchArtifacts } from "./dispatch.mjs";

export function runIssueDispatch(config, graph, issue) {
  let dispatch = createDispatch(config, graph, issue);
  const runDir = writeDispatchArtifacts(config, dispatch);

  if (config.execute && dispatch.state !== "refused") {
    dispatch = executeDispatch(config, dispatch);
    writeDispatchArtifacts(config, dispatch);
  }

  return { runDir, dispatch };
}
