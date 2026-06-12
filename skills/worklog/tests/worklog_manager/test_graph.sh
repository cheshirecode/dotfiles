#!/usr/bin/env bash
# Fixture-backed smoke test for the worklog graph exporter/viewer.

set -euo pipefail

WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."
FIXTURE="$(pwd)/tests/worklog_manager/fixtures/projects"
SCRATCH="$(mktemp -d -t worklog-manager-graph-test-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

JSON_OUT="$SCRATCH/graph.json"
HTML_OUT="$SCRATCH/graph.html"
DOT_OUT="$SCRATCH/graph.dot"

"$WORKLOG_BIN/worklog-manager" graph \
  --repo "$FIXTURE" \
  --instance fixture-projects \
  --github-repo example/projects-ui \
  --format json \
  --output "$JSON_OUT"

node - "$JSON_OUT" <<'NODE'
const fs = require("node:fs");
const graph = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
assert(graph.schemaVersion === "worklog.graph.v1", "unexpected graph schema");
assert(graph.instance.name === "fixture-projects", "instance name not preserved");
assert(graph.instance.github.repos.includes("example/projects-ui"), "github repo metadata missing");
assert(graph.summary.nodeCount === 3, `expected 3 nodes, got ${graph.summary.nodeCount}`);
assert(graph.summary.edgeCount === 5, `expected 5 edges, got ${graph.summary.edgeCount}`);
assert(graph.summary.diagnosticCount === 0, `expected no diagnostics, got ${graph.summary.diagnosticCount}`);
assert(graph.nodes.some((node) => node.id === "projects-root"), "missing root task");
assert(graph.nodes.some((node) => node.id === "projects-child"), "missing child task");
assert(graph.nodes.some((node) => node.id === "projects-archive"), "missing archived task");
assert(graph.edges.some((edge) => edge.source === "projects-root" && edge.target === "projects-child" && edge.relation === "parent"), "missing parent edge");
assert(graph.edges.some((edge) => edge.source === "projects-root" && edge.target === "projects-child" && edge.relation === "related"), "missing related edge");
assert(graph.edges.some((edge) => edge.source === "projects-root" && edge.target === "projects-archive" && edge.relation === "parent"), "missing archived parent edge");
assert(graph.edges.some((edge) => edge.source === "projects-root" && edge.target === "projects-archive" && edge.relation === "related"), "missing archived related edge");
assert(graph.edges.some((edge) => edge.source === "projects-root" && edge.target === "projects-child" && edge.relation === "depends_on"), "missing depends_on edge");
NODE

ACTIVE_JSON_OUT="$SCRATCH/active-graph.json"
"$WORKLOG_BIN/worklog-manager" graph \
  --repo "$FIXTURE" \
  --instance fixture-projects \
  --active-only \
  --format json \
  --output "$ACTIVE_JSON_OUT"

node - "$ACTIVE_JSON_OUT" <<'NODE'
const fs = require("node:fs");
const graph = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
assert(graph.summary.unresolvedEdgeCount === 0, `expected no unresolved edges, got ${graph.summary.unresolvedEdgeCount}`);
assert(graph.nodes.some((node) => node.id === "projects-root"), "missing active root task");
assert(graph.nodes.some((node) => node.id === "projects-child"), "missing active child task");
assert(!graph.nodes.some((node) => node.id === "projects-archive"), "active-only leaked archived task");
assert(!graph.edges.some((edge) => edge.target === "projects-archive"), "active-only leaked archived edge");
NODE

"$WORKLOG_BIN/worklog-manager" graph \
  --repo "$FIXTURE" \
  --instance fixture-projects \
  --project projects-root \
  --match projects-child \
  --format html \
  --output "$HTML_OUT"

grep -q '<title>Worklog Graph - fixture-projects</title>' "$HTML_OUT"
grep -q 'function layout(nodes,edges)' "$HTML_OUT"
grep -q 'parentNode' "$HTML_OUT"
grep -q 'data-relation="depends_on"' "$HTML_OUT"
grep -q 'function nodeTags(n)' "$HTML_OUT"
grep -q '"projects-root"' "$HTML_OUT"
grep -q '"projects-child"' "$HTML_OUT"

"$WORKLOG_BIN/worklog-manager" graph \
  --repo "$FIXTURE" \
  --format dot \
  --active-only \
  --output "$DOT_OUT"

grep -q 'digraph worklog' "$DOT_OUT"
grep -q '"projects-root" -> "projects-child" \[label="parent"' "$DOT_OUT"

echo "worklog-manager graph fixture test passed"
