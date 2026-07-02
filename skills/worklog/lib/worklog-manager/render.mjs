import fs from "node:fs";
import path from "node:path";

const STATUS_COLORS = {
  draft: "#94a3b8",
  "in-progress": "#2563eb",
  "in-review": "#7c3aed",
  blocked: "#dc2626",
  shipping: "#d97706",
  archived: "#64748b",
  project: "#0f766e",
};

const DEFAULT_RELATIONS = new Set(["parent", "project", "reopens", "supersedes", "superseded_by", "depends_on"]);

function quoteDot(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

export function renderDot(graph) {
  const lines = [
    "digraph worklog {",
    "  graph [rankdir=LR, overlap=false, splines=true];",
    "  node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\"];",
    "  edge [fontname=\"Helvetica\", color=\"#64748b\"];",
  ];

  for (const node of graph.nodes) {
    const color = STATUS_COLORS[node.status] || STATUS_COLORS[node.state] || "#64748b";
    const label = `${node.slug}\\n${node.status || node.state} / ${node.kind}`;
    lines.push(`  ${quoteDot(node.id)} [label=${quoteDot(label)}, fillcolor=${quoteDot(color)}, fontcolor="#ffffff", tooltip=${quoteDot(node.file || node.slug)}];`);
  }

  for (const edge of graph.edges) {
    lines.push(`  ${quoteDot(edge.source)} -> ${quoteDot(edge.target)} [label=${quoteDot(edge.relation)}, tooltip=${quoteDot(edge.note || edge.relation)}];`);
  }
  lines.push("}");
  return `${lines.join("\n")}\n`;
}

export function renderHtml(graph) {
  const dot = renderDot(graph);
  const instanceName = graph.instance?.name || "worklog";
  const worklogRepo = graph.instance?.roots?.worklogRepo || "";
  const nodeCount = graph.summary?.nodeCount || graph.nodes.length;
  const edgeCount = graph.summary?.edgeCount || graph.edges.length;
  const diagnosticCount = graph.summary?.diagnosticCount || 0;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Worklog Graph - ${escapeHtml(instanceName)}</title>
<style>
${renderStyleSheet()}
</style>
</head>
<body>
${renderHeader(instanceName, worklogRepo)}
${renderControls(graph)}
${renderMain()}
<script>
${renderClientScript({ graph, dot, instanceName, nodeCount, edgeCount, diagnosticCount, worklogRepo })}
</script>
</body>
</html>
`;
}

function renderHeader(instanceName, worklogRepo) {
  return `<header><div><h1>Worklog Graph</h1><div class="meta" id="summary"></div></div><div class="meta" id="repo">${escapeHtml(worklogRepo)}</div></header>`;
}

function renderControls(graph) {
  const stateSet = new Set(graph.nodes.map((node) => node.state));
  const relationSet = new Set(graph.edges.map((edge) => edge.relation));
  const filterActive = Boolean((graph.instance?.filter?.projects || []).length || (graph.instance?.filter?.matches || []).length);
  const checkedState = (state) => (
    state === "active" || state === "project" || (filterActive && stateSet.has(state))
  ) ? " checked" : "";
  const checkedRelation = (relation) => (
    DEFAULT_RELATIONS.has(relation) || (filterActive && relationSet.has(relation))
  ) ? " checked" : "";

  return `<section class="controls">
<input id="search" type="search" list="slugs" placeholder="Search slug">
<datalist id="slugs"></datalist>
<button id="fit" type="button">Fit</button>
<button id="zoomOut" type="button">-</button>
<button id="zoomIn" type="button">+</button>
<button id="reset" type="button">Reset</button>
<button id="toggleDetails" type="button">Details</button>
${stateCheckbox("active", "active", checkedState)}
${stateCheckbox("archive", "archive", checkedState)}
${stateCheckbox("project", "projects", checkedState)}
${relationCheckbox("parent", "parent", checkedRelation)}
${relationCheckbox("related", "related", checkedRelation)}
${relationCheckbox("project", "project", checkedRelation)}
${relationCheckbox("reopens", "reopens", checkedRelation)}
${relationCheckbox("supersedes", "supersedes", checkedRelation)}
${relationCheckbox("superseded_by", "superseded", checkedRelation)}
${relationCheckbox("depends_on", "depends on", checkedRelation)}
<span class="chip" id="visibleStats"></span>
</section>`;
}

function stateCheckbox(state, label, checkedState) {
  return `<label><input type="checkbox" data-state="${state}"${checkedState(state)}> ${label} <span class="count" id="count-state-${state}"></span></label>`;
}

function relationCheckbox(relation, label, checkedRelation) {
  return `<label><input type="checkbox" data-relation="${relation}"${checkedRelation(relation)}> ${label} <span class="count" id="count-rel-${relation}"></span></label>`;
}

function renderMain() {
  return `<main>
<section id="stage"><div id="canvas"><svg id="edges"></svg></div></section>
<aside>
<section class="nextPanel">
<div class="panelHead"><h2>Active Next Actions</h2><span id="nextActionCount"></span></div>
<div id="nextActions"></div>
</section>
<div id="details"><h2>No node selected</h2><div class="field">Search or select a task to inspect its focused neighborhood.</div></div>
<div id="diagnostics"></div>
<details id="debug"><summary>DOT export</summary><pre id="dot"></pre></details>
</aside>
</main>`;
}

function renderStyleSheet() {
  return `
html,body{width:100%;height:100%;overflow:hidden}
*{box-sizing:border-box}
body{margin:0;background:#f5f7fa;color:#172033;font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:grid;grid-template-rows:auto auto minmax(0,1fr);height:100dvh}
header{display:flex;justify-content:space-between;gap:16px;align-items:center;background:#fff;border-bottom:1px solid #d7dce4;padding:12px 16px;min-width:0}
h1{font-size:24px;margin:0}
.meta{font-size:12px;color:#5d6778;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center;background:#fff;border-bottom:1px solid #d7dce4;padding:8px 12px;min-width:0}
.controls label,.chip{font-size:13px;white-space:nowrap}
.controls label{display:inline-flex;align-items:center;gap:5px;min-height:32px;padding:2px 0}
.controls input[type=checkbox]{width:18px;height:18px;flex:0 0 auto}
.controls input[type=search]{width:min(320px,100%);padding:7px 9px;border:1px solid #bec7d4;border-radius:6px}
.controls button{border:1px solid #bec7d4;background:#fff;border-radius:6px;padding:7px 9px;color:#172033;cursor:pointer}
.controls button:hover{border-color:#64748b}
.count{color:#64748b}
main{display:grid;grid-template-columns:minmax(0,1fr)minmax(340px,420px);min-height:0}
body.details-collapsed main{grid-template-columns:minmax(0,1fr)0}
body.details-collapsed aside{display:none}
#stage{position:relative;overflow:hidden;background:#eef1f5;min-width:0;min-height:0;touch-action:none;cursor:grab}
#stage.panning{cursor:grabbing}
#canvas{position:absolute;left:0;top:0;transform-origin:0 0;will-change:transform}
#edges{position:absolute;inset:0;pointer-events:none;overflow:visible}
.edgeLabel{font-size:11px;font-weight:700;fill:#334155;paint-order:stroke;stroke:#eef1f5;stroke-width:4px;stroke-linejoin:round;pointer-events:none}
.node{position:absolute;width:230px;min-height:78px;box-sizing:border-box;border:1px solid #c6ceda;border-radius:8px;background:#fff;box-shadow:0 2px 8px rgba(24,34,52,.08);padding:11px 12px;cursor:pointer}
.node.parentNode{background:#f8fbff;border-color:#9fb0c6;box-shadow:0 4px 14px rgba(24,34,52,.13)}
.node.childNode{background:#fff}
.node:hover,.node.selected{border-color:#334155;box-shadow:0 5px 16px rgba(24,34,52,.16)}
.node.selected{outline:2px solid #172033;outline-offset:2px}
.slug{font-weight:700;font-size:14px;overflow-wrap:anywhere}
.tags{margin-top:7px;display:flex;gap:5px;flex-wrap:wrap}
.tag{font-size:11px;color:#334155;background:#eef2f7;border-radius:999px;padding:2px 6px}
.empty{position:absolute;inset:0;display:grid;place-items:center;color:#5d6778;text-align:center;padding:24px}
aside{border-left:1px solid #d7dce4;background:#fff;overflow:auto;min-width:0}
.nextPanel{border-bottom:1px solid #d7dce4;padding:12px 14px}
.panelHead{display:flex;justify-content:space-between;gap:10px;align-items:center;margin-bottom:8px}
.panelHead h2{font-size:16px;margin:0}
#nextActionCount{font-size:12px;color:#64748b;white-space:nowrap}
#nextActions{display:grid;gap:6px;max-height:34dvh;overflow-y:auto;overflow-x:hidden;padding-right:2px}
.actionRow{width:100%;min-width:0;overflow:hidden;border:1px solid #d7dce4;background:#fbfcfe;border-radius:8px;padding:8px;text-align:left;color:#172033;cursor:pointer}
.actionRow:hover,.actionRow.selected{border-color:#334155;background:#f8fbff}
.actionSlug{font-weight:700;font-size:13px;overflow-wrap:anywhere}
.actionMeta{margin-top:3px;color:#64748b;font-size:11px;overflow:hidden;overflow-wrap:anywhere;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.actionNext{margin-top:5px;font-size:12px;line-height:1.35;color:#334155;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
#details{padding:14px;border-bottom:1px solid #d7dce4;font-size:13px}
#details h2{font-size:20px;margin:0 0 8px;overflow-wrap:anywhere}
.field{margin-top:4px}
.edgeGroup{margin-top:10px}
.edgeGroup strong{display:block;margin-bottom:3px}
.edgeGroup div{color:#334155;line-height:1.35}
.reveal{margin:4px 6px 0 0;border:1px solid #bec7d4;background:#f8fafc;border-radius:6px;padding:4px 7px;color:#172033;cursor:pointer}
.diagSummary{border-bottom:1px solid #d7dce4;background:#fff7ed;color:#7c2d12;font-size:12px}
.diagSummary summary{cursor:pointer;padding:10px 14px;font-weight:700}
.diag{padding:0 14px 10px}
.diag+.diag{border-top:1px solid #fed7aa;padding-top:10px}
.diag strong{display:block;margin-bottom:4px}
#debug{border-top:1px solid #d7dce4}
#debug summary{padding:10px 14px;cursor:pointer;color:#334155;font-size:12px}
pre{margin:0;padding:14px;overflow:auto;font-size:11px;line-height:1.45;background:#fbfcfe;max-height:34vh}
@media(max-width:900px){
  header{display:block;padding:10px 12px}
  .meta{white-space:normal;overflow-wrap:anywhere}
  .controls{display:flex;flex-wrap:wrap;gap:6px;overflow:visible;padding:8px 10px}
  .controls input[type=search]{flex:1 1 180px;width:auto;min-width:0}
  .controls button{flex:0 0 auto;width:auto;padding:6px 8px}
  .controls label{display:inline-flex;align-items:center;gap:4px;flex:0 1 auto;min-width:0;min-height:28px;font-size:12px;white-space:nowrap}
  .controls input[type=checkbox]{width:16px;height:16px}
  .chip{flex:1 0 100%;white-space:nowrap}
  .count{flex:0 0 auto}
  main{grid-template-columns:1fr;grid-template-rows:minmax(0,1fr)minmax(220px,45dvh)}
  body.details-collapsed main{grid-template-rows:minmax(0,1fr)0}
  aside{border-left:0;border-top:1px solid #d7dce4}
  .node{width:216px}
  #nextActions{max-height:20dvh}
}`;
}

function renderClientScript({ graph, dot, instanceName, nodeCount, edgeCount, diagnosticCount, worklogRepo }) {
  return `
const graph = ${scriptJson(graph)};
const dot = ${scriptJson(dot)};
const statusColors = ${scriptJson(STATUS_COLORS)};
const stage = document.getElementById("stage");
const canvas = document.getElementById("canvas");
const edgeSvg = document.getElementById("edges");
const search = document.getElementById("search");
const CARD_W = 230;
const CARD_H = 78;
const COL_GAP = 34;
const ROW_GAP = 26;
const PAD = 32;
let view = { x: 0, y: 0, scale: 1 };
let selectedId = "";
let canvasSize = { w: 800, h: 600 };
let lastVisible = { nodes: [], edges: [] };
let userMoved = false;

document.getElementById("dot").textContent = dot;
document.getElementById("summary").textContent = ${JSON.stringify(instanceName)} + " - " + ${nodeCount} + " nodes, " + ${edgeCount} + " edges, " + ${diagnosticCount} + " diagnostics";
document.getElementById("repo").textContent = ${JSON.stringify(worklogRepo)};
document.getElementById("slugs").innerHTML = graph.nodes
  .filter(function(n) { return n.type === "task"; })
  .map(function(n) { return '<option value="' + esc(n.slug) + '"></option>'; })
  .join("");

function esc(s) {
  return String(s || "").replace(/[&<>"']/g, function(ch) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
  });
}

function checked(selector, attr) {
  return new Set(Array.from(document.querySelectorAll(selector))
    .filter(function(input) { return input.checked; })
    .map(function(input) { return input.getAttribute(attr); }));
}

function selectedRelations() {
  return checked("input[data-relation]", "data-relation");
}

function selectedStates() {
  return checked("input[data-state]", "data-state");
}

function exactSearch() {
  const q = search.value.trim().toLowerCase();
  if (!q) return null;
  return graph.nodes.find(function(n) {
    return n.slug.toLowerCase() === q || n.id.toLowerCase() === q;
  }) || null;
}

function hay(n) {
  return [
    n.slug,
    n.status,
    n.kind,
    n.okfType,
    n.worklogId,
    n.timestamp,
    n.project,
    n.file
  ].concat(n.repos || []).join(" ").toLowerCase();
}

function countBy(items, keyFn) {
  const out = {};
  for (const item of items) {
    const key = keyFn(item) || "";
    out[key] = (out[key] || 0) + 1;
  }
  return out;
}

function nodeTags(n){
  const raw = n.type === "project" ? [n.type] : [n.status || n.state, n.kind, n.ldap];
  const out = [];
  for (const item of raw) {
    const value = String(item || "").trim();
    if (value && !out.includes(value)) out.push(value);
  }
  return out.length ? out : ["-"];
}

function setupCounts() {
  const states = countBy(graph.nodes, function(n) { return n.state; });
  const relations = countBy(graph.edges, function(e) { return e.relation; });
  for (const key of Object.keys(states)) {
    const el = document.getElementById("count-state-" + key);
    if (el) el.textContent = "(" + states[key] + ")";
  }
  for (const key of Object.keys(relations)) {
    const el = document.getElementById("count-rel-" + key);
    if (el) el.textContent = "(" + relations[key] + ")";
  }
}

function actionDate(n) {
  return Date.parse(n.frontmatter && n.frontmatter.last_updated || n.timestamp || "") || 0;
}

function renderNextActions() {
  const tasks = graph.nodes
    .filter(function(n) { return n.type === "task" && n.state === "active"; })
    .sort(function(a, b) {
      const byDate = actionDate(b) - actionDate(a);
      return byDate || a.slug.localeCompare(b.slug);
    });
  document.getElementById("nextActionCount").textContent = tasks.length + " active";
  document.getElementById("nextActions").innerHTML = tasks.map(function(n) {
    const next = n.frontmatter && n.frontmatter.next_action || "-";
    const selected = n.id === selectedId ? " selected" : "";
    return '<button type="button" class="actionRow' + selected + '" data-next-action-row data-node-id="' + esc(n.id) + '">'
      + '<div class="actionSlug">' + esc(n.slug) + '</div>'
      + '<div class="actionMeta">' + esc([n.status || n.state, n.project || "none", n.file || "-"].join(" / ")) + '</div>'
      + '<div class="actionNext">' + esc(next) + '</div>'
      + '</button>';
  }).join("");
}

function diagnosticsHtml() {
  const diagnostics = graph.diagnostics || [];
  if (!diagnostics.length) return "";
  const grouped = new Map();
  for (const d of diagnostics) {
    const key = [d.level, d.code, d.message, d.file].join("\\n");
    const item = grouped.get(key) || { ...d, count: 0 };
    item.count += 1;
    grouped.set(key, item);
  }
  const items = Array.from(grouped.values());
  const hasError = items.some(function(d) { return d.level === "error"; });
  return '<details class="diagSummary" ' + (hasError ? "open" : "") + '><summary>'
    + diagnostics.length + ' diagnostics, ' + items.length + ' grouped</summary>'
    + items.slice(0, 8).map(function(d) {
      return '<div class="diag"><strong>' + esc(d.level + " " + d.code) + (d.count > 1 ? " x" + d.count : "")
        + '</strong>' + esc(d.message) + '<br>' + esc(d.file || "") + '</div>';
    }).join("")
    + (items.length > 8 ? '<div class="diag">... ' + (items.length - 8) + ' more groups</div>' : "")
    + '</details>';
}

function neighborhood(rootId, depth, relations) {
  const ids = new Set([rootId]);
  let frontier = new Set([rootId]);
  for (let i = 0; i < depth; i += 1) {
    const next = new Set();
    for (const edge of graph.edges) {
      if (!relations.has(edge.relation)) continue;
      if (frontier.has(edge.source) && !ids.has(edge.target)) {
        ids.add(edge.target);
        next.add(edge.target);
      }
      if (frontier.has(edge.target) && !ids.has(edge.source)) {
        ids.add(edge.source);
        next.add(edge.source);
      }
    }
    frontier = next;
  }
  return ids;
}

function visible() {
  const states = selectedStates();
  const relations = selectedRelations();
  const q = search.value.trim().toLowerCase();
  const exact = exactSearch();
  if (exact) selectedId = exact.id;

  let ids = null;
  if (selectedId) ids = neighborhood(selectedId, 2, relations);

  let nodes = graph.nodes.filter(function(n) {
    return (states.has(n.state) || n.id === selectedId) && (!ids || ids.has(n.id));
  });
  if (q && !exact && !selectedId) {
    nodes = nodes.filter(function(n) { return hay(n).includes(q); });
  }
  const nodeIds = new Set(nodes.map(function(n) { return n.id; }));
  const edges = graph.edges.filter(function(e) {
    return nodeIds.has(e.source) && nodeIds.has(e.target) && relations.has(e.relation);
  });
  return { nodes, edges };
}

function nodeOrder(a, b) {
  const ak = (a.project || "zz") + " " + (a.kind === "project" ? "0" : "1") + " " + (a.status || "") + " " + a.slug;
  const bk = (b.project || "zz") + " " + (b.kind === "project" ? "0" : "1") + " " + (b.status || "") + " " + b.slug;
  return ak.localeCompare(bk);
}

function placeRows(rows, cols, stageW) {
  const pos = new Map();
  let y = PAD;
  for (const row of rows) {
    const sorted = Array.from(row).sort(nodeOrder);
    const lines = Math.max(1, Math.ceil(sorted.length / cols));
    for (let line = 0; line < lines; line += 1) {
      const slice = sorted.slice(line * cols, (line + 1) * cols);
      const used = slice.length * CARD_W + Math.max(0, slice.length - 1) * COL_GAP;
      const start = Math.max(PAD, (stageW - used) / 2);
      slice.forEach(function(n, i) {
        pos.set(n.id, { x: start + i * (CARD_W + COL_GAP), y: y + line * (CARD_H + ROW_GAP) });
      });
    }
    y += lines * (CARD_H + ROW_GAP) + ROW_GAP;
  }
  return pos;
}

function layout(nodes,edges){
  const stageW = Math.max(320, stage.clientWidth || 900);
  const cols = Math.max(1, Math.floor((stageW - PAD * 2 + COL_GAP) / (CARD_W + COL_GAP)));
  const ids = new Set(nodes.map(function(n) { return n.id; }));
  const parentEdges = edges.filter(function(e) {
    return e.relation === "parent" && ids.has(e.source) && ids.has(e.target);
  });

  if (!parentEdges.length) {
    const sorted = Array.from(nodes).sort(nodeOrder);
    if (selectedId) {
      sorted.sort(function(a, b) {
        if (a.id === selectedId) return -1;
        if (b.id === selectedId) return 1;
        return 0;
      });
    }
    return placeRows([sorted], cols, stageW);
  }

  const children = new Map();
  const incoming = new Map(nodes.map(function(n) { return [n.id, 0]; }));
  for (const edge of parentEdges) {
    if (!children.has(edge.source)) children.set(edge.source, []);
    children.get(edge.source).push(edge.target);
    incoming.set(edge.target, (incoming.get(edge.target) || 0) + 1);
  }

  const rank = new Map();
  const queue = [];
  for (const node of nodes) {
    if ((incoming.get(node.id) || 0) === 0 && (children.get(node.id) || []).length) {
      rank.set(node.id, 0);
      queue.push(node.id);
    }
  }
  for (let i = 0; i < queue.length; i += 1) {
    const id = queue[i];
    const nextRank = (rank.get(id) || 0) + 1;
    for (const child of children.get(id) || []) {
      if (!rank.has(child) || rank.get(child) < nextRank) {
        rank.set(child, nextRank);
        queue.push(child);
      }
    }
  }
  const maxRank = Math.max(0, ...rank.values());
  for (const node of nodes) {
    if (!rank.has(node.id)) rank.set(node.id, (children.get(node.id) || []).length ? 0 : maxRank + 1);
  }
  const rows = [];
  for (const node of nodes) {
    const row = rank.get(node.id);
    if (!rows[row]) rows[row] = [];
    rows[row].push(node);
  }
  return placeRows(rows.filter(Boolean), cols, stageW);
}

function relationColor(rel) {
  return {
    parent: "#2563eb",
    project: "#0f766e",
    related: "#64748b",
    reopens: "#d97706",
    supersedes: "#7c3aed",
    superseded_by: "#7c3aed",
    depends_on: "#0891b2"
  }[rel] || "#64748b";
}

function markerId(rel) {
  return "arrow-" + String(rel).replace(/[^a-zA-Z0-9_-]/g, "_");
}

function addEdgeMarkers(edges) {
  const defs = document.createElementNS("http://www.w3.org/2000/svg", "defs");
  for (const rel of Array.from(new Set(edges.map(function(e) { return e.relation; })))) {
    const marker = document.createElementNS("http://www.w3.org/2000/svg", "marker");
    const head = document.createElementNS("http://www.w3.org/2000/svg", "path");
    marker.setAttribute("id", markerId(rel));
    marker.setAttribute("viewBox", "0 0 10 10");
    marker.setAttribute("refX", "9");
    marker.setAttribute("refY", "5");
    marker.setAttribute("markerWidth", "7");
    marker.setAttribute("markerHeight", "7");
    marker.setAttribute("orient", "auto");
    head.setAttribute("d", "M 0 0 L 10 5 L 0 10 z");
    head.setAttribute("fill", relationColor(rel));
    marker.appendChild(head);
    defs.appendChild(marker);
  }
  edgeSvg.appendChild(defs);
}

function applyView() {
  canvas.style.transform = "translate(" + view.x + "px," + view.y + "px) scale(" + view.scale + ")";
}

function fitView() {
  const rect = stage.getBoundingClientRect();
  const mobile = rect.width < 700;
  const fitWidth = (rect.width - 32) / canvasSize.w;
  const fitAll = Math.min((rect.width - 48) / canvasSize.w, (rect.height - 48) / canvasSize.h);
  const scale = Math.max(mobile ? 0.72 : 0.25, Math.min(1.25, mobile ? fitWidth : fitAll));
  view = {
    scale,
    x: (rect.width - canvasSize.w * scale) / 2,
    y: mobile ? 16 : (rect.height - canvasSize.h * scale) / 2
  };
  applyView();
  userMoved = false;
}

function resetView() {
  view = { x: 24, y: 24, scale: 1 };
  applyView();
  userMoved = true;
}

function zoomAt(factor, cx, cy) {
  const next = Math.max(0.2, Math.min(3, view.scale * factor));
  const wx = (cx - view.x) / view.scale;
  const wy = (cy - view.y) / view.scale;
  view.x = cx - wx * next;
  view.y = cy - wy * next;
  view.scale = next;
  applyView();
  userMoved = true;
}

function renderNode(n, pos, parentIds, childIds) {
  const p = pos.get(n.id);
  if (!p) return;
  const color = statusColors[n.status] || statusColors[n.state] || "#64748b";
  const el = document.createElement("div");
  el.className = "node" + (parentIds.has(n.id) ? " parentNode" : "") + (childIds.has(n.id) ? " childNode" : "") + (n.id === selectedId ? " selected" : "");
  el.dataset.id = n.id;
  el.style.left = p.x + "px";
  el.style.top = p.y + "px";
  el.style.borderColor = color;
  el.innerHTML = '<div class="slug">' + esc(n.slug) + '</div><div class="tags">'
    + nodeTags(n).map(function(tag) { return '<span class="tag">' + esc(tag) + '</span>'; }).join("")
    + '</div>';
  el.addEventListener("click", function(ev) {
    ev.stopPropagation();
    selectNodeById(n.id, true);
    if (window.matchMedia("(max-width:900px)").matches) {
      document.body.classList.remove("details-collapsed");
      updateDetailsToggle();
    }
  });
  canvas.appendChild(el);
}

function renderEdge(edge, pos) {
  const a = pos.get(edge.source);
  const b = pos.get(edge.target);
  if (!a || !b) return;

  let x1 = a.x + CARD_W / 2;
  let y1 = a.y + CARD_H / 2;
  let x2 = b.x + CARD_W / 2;
  let y2 = b.y + CARD_H / 2;
  const dx = x2 - x1;
  const dy = y2 - y1;
  if (Math.abs(dx) > Math.abs(dy)) {
    const sx = dx >= 0 ? 1 : -1;
    x1 += sx * CARD_W / 2;
    x2 -= sx * CARD_W / 2;
  } else {
    const sy = dy >= 0 ? 1 : -1;
    y1 += sy * CARD_H / 2;
    y2 -= sy * CARD_H / 2;
  }

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("d", "M " + x1 + " " + y1 + " C " + x1 + " " + ((y1 + y2) / 2) + ", " + x2 + " " + ((y1 + y2) / 2) + ", " + x2 + " " + y2);
  path.setAttribute("stroke", relationColor(edge.relation));
  path.setAttribute("stroke-width", edge.relation === "parent" ? "2" : (selectedId && (edge.source === selectedId || edge.target === selectedId) ? "2.2" : "1.2"));
  path.setAttribute("fill", "none");
  path.setAttribute("opacity", edge.relation === "parent" ? ".72" : (selectedId && edge.source !== selectedId && edge.target !== selectedId ? ".22" : ".5"));
  path.setAttribute("marker-end", "url(#" + markerId(edge.relation) + ")");
  edgeSvg.appendChild(path);

  const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
  label.classList.add("edgeLabel");
  label.setAttribute("x", (x1 + x2) / 2);
  label.setAttribute("y", (y1 + y2) / 2 - 6);
  label.setAttribute("text-anchor", "middle");
  label.textContent = edge.relation.replaceAll("_", " ");
  edgeSvg.appendChild(label);
}

function render() {
  const vg = visible();
  const pos = layout(vg.nodes,vg.edges);
  lastVisible = vg;
  canvas.querySelectorAll(".node,.empty").forEach(function(node) { node.remove(); });
  edgeSvg.innerHTML = "";
  addEdgeMarkers(vg.edges);

  let maxX = stage.clientWidth;
  let maxY = stage.clientHeight;
  for (const p of pos.values()) {
    maxX = Math.max(maxX, p.x + CARD_W + PAD);
    maxY = Math.max(maxY, p.y + CARD_H + PAD);
  }
  canvasSize = { w: maxX, h: maxY };
  canvas.style.width = maxX + "px";
  canvas.style.height = maxY + "px";
  edgeSvg.setAttribute("width", maxX);
  edgeSvg.setAttribute("height", maxY);

  if (!vg.nodes.length) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = "No visible tasks. Relax filters or search another slug.";
    canvas.appendChild(empty);
  }

  const parentIds = new Set(vg.edges.filter(function(e) { return e.relation === "parent"; }).map(function(e) { return e.source; }));
  const childIds = new Set(vg.edges.filter(function(e) { return e.relation === "parent"; }).map(function(e) { return e.target; }));
  for (const node of vg.nodes) renderNode(node, pos, parentIds, childIds);
  for (const edge of vg.edges) renderEdge(edge, pos);

  document.getElementById("visibleStats").textContent = vg.nodes.length + " visible nodes, " + vg.edges.length + " visible edges";
  renderNextActions();
  if (!userMoved) fitView();
  if (selectedId) {
    const node = graph.nodes.find(function(n) { return n.id === selectedId; });
    if (node) selectNode(node, vg);
  } else {
    resetDetails();
  }
}

function groupName(edge, node) {
  if (edge.relation === "parent") return edge.target === node.id ? "Parents" : "Children";
  if (edge.relation === "depends_on") return edge.target === node.id ? "Depends on" : "Required by";
  if (edge.relation === "project") return "Same project";
  if (edge.relation === "related") return "Related";
  if (edge.relation === "reopens") return "Reopens";
  if (edge.relation === "supersedes" || edge.relation === "superseded_by") return "Supersedes";
  return edge.relation;
}

function edgeLine(edge) {
  return esc(edge.source) + " -> " + esc(edge.target) + (edge.note ? ": " + esc(edge.note) : "");
}

function resetDetails() {
  document.getElementById("details").innerHTML = '<h2>No node selected</h2><div class="field">Search or select a task to inspect its focused neighborhood.</div>';
}

function selectNode(node, vg) {
  const visibleEdgeIds = new Set(vg.edges.map(function(edge) { return edge.id; }));
  const incident = graph.edges.filter(function(edge) {
    return edge.source === node.id || edge.target === node.id;
  });
  const hidden = incident.filter(function(edge) { return !visibleEdgeIds.has(edge.id); });
  const groups = {};
  for (const edge of incident.filter(function(edge) { return visibleEdgeIds.has(edge.id); })) {
    const key = groupName(edge, node);
    if (!groups[key]) groups[key] = [];
    groups[key].push(edge);
  }

  let html = '<h2>' + esc(node.slug) + '</h2>'
    + '<div class="field"><b>Status:</b> ' + esc(node.status || node.state) + ' / ' + esc(node.kind) + '</div>'
    + '<div class="field"><b>OKF:</b> ' + esc(node.okfType || "-") + ' / ' + esc(node.worklogId || "-") + ' / ' + esc(node.timestamp || "-") + '</div>'
    + '<div class="field"><b>Next:</b> ' + esc(node.frontmatter && node.frontmatter.next_action || "-") + '</div>'
    + '<div class="field"><b>File:</b> ' + esc(node.file || "-") + '</div>'
    + '<div class="field"><b>Project:</b> ' + esc(node.project || "-") + '</div>'
    + '<div class="field"><b>Repos:</b> ' + esc((node.repos || []).join(", ") || "-") + '</div>';

  html += '<div class="edgeGroup"><strong>Visible relation groups</strong>';
  for (const key of Object.keys(groups)) {
    const items = groups[key];
    html += '<div><b>' + esc(key) + '</b> (' + items.length + ')<br>'
      + items.slice(0, 8).map(edgeLine).join("<br>")
      + (items.length > 8 ? "<br>..." : "")
      + '</div>';
  }
  if (!Object.keys(groups).length) html += '<div>-</div>';
  html += '</div>';

  if (hidden.length) {
    const relations = Array.from(new Set(hidden.map(function(edge) { return edge.relation; })));
    const states = Array.from(new Set(hidden.flatMap(function(edge) {
      const source = graph.nodes.find(function(item) { return item.id === edge.source; });
      const target = graph.nodes.find(function(item) { return item.id === edge.target; });
      return [source && source.state, target && target.state];
    }).filter(Boolean).filter(function(state) { return !selectedStates().has(state); })));
    html += '<div class="edgeGroup"><strong>Hidden incident edges: ' + hidden.length + '</strong>';
    for (const relation of relations) {
      if (!selectedRelations().has(relation)) {
        html += '<button class="reveal" data-reveal-relation="' + esc(relation) + '">Show ' + esc(relation) + '</button>';
      }
    }
    for (const state of states) {
      html += '<button class="reveal" data-reveal-state="' + esc(state) + '">Show ' + esc(state) + '</button>';
    }
    html += '</div>';
  }
  document.getElementById("details").innerHTML = html;
}

function selectNodeById(id, updateSearch) {
  const node = graph.nodes.find(function(item) { return item.id === id; });
  if (!node) return;
  selectedId = node.id;
  if (updateSearch) search.value = node.slug;
  userMoved = false;
  render();
}

function wirePointerControls() {
  const pointers = new Map();
  let panStart = null;
  let pinchStart = null;

  stage.addEventListener("pointerdown", function(ev) {
    if (ev.target.closest(".node,button,input,label")) return;
    stage.setPointerCapture(ev.pointerId);
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (pointers.size === 1) {
      panStart = { x: ev.clientX, y: ev.clientY, vx: view.x, vy: view.y };
      stage.classList.add("panning");
    }
    if (pointers.size === 2) {
      const pts = Array.from(pointers.values());
      pinchStart = {
        dist: Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y),
        x: (pts[0].x + pts[1].x) / 2,
        y: (pts[0].y + pts[1].y) / 2
      };
    }
  });

  stage.addEventListener("pointermove", function(ev) {
    if (!pointers.has(ev.pointerId)) return;
    pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (pointers.size === 2 && pinchStart) {
      const pts = Array.from(pointers.values());
      const dist = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
      zoomAt(dist / pinchStart.dist, pinchStart.x, pinchStart.y);
      pinchStart.dist = dist;
      return;
    }
    if (panStart) {
      view.x = panStart.vx + ev.clientX - panStart.x;
      view.y = panStart.vy + ev.clientY - panStart.y;
      applyView();
      userMoved = true;
    }
  });

  function endPointer(ev) {
    pointers.delete(ev.pointerId);
    panStart = null;
    pinchStart = null;
    stage.classList.remove("panning");
  }
  stage.addEventListener("pointerup", endPointer);
  stage.addEventListener("pointercancel", endPointer);
  stage.addEventListener("wheel", function(ev) {
    ev.preventDefault();
    const rect = stage.getBoundingClientRect();
    zoomAt(ev.deltaY < 0 ? 1.12 : 0.88, ev.clientX - rect.left, ev.clientY - rect.top);
  }, { passive: false });
}

const detailsToggle = document.getElementById("toggleDetails");
function updateDetailsToggle() {
  detailsToggle.textContent = document.body.classList.contains("details-collapsed") ? "Show details" : "Hide details";
}

document.getElementById("diagnostics").innerHTML = diagnosticsHtml();
document.getElementById("nextActions").addEventListener("click", function(ev) {
  const row = ev.target.closest("[data-next-action-row]");
  if (!row) return;
  selectNodeById(row.getAttribute("data-node-id"), true);
});
document.getElementById("details").addEventListener("click", function(ev) {
  const rel = ev.target.getAttribute("data-reveal-relation");
  const state = ev.target.getAttribute("data-reveal-state");
  if (rel) {
    const input = document.querySelector('input[data-relation="' + rel + '"]');
    if (input) input.checked = true;
  }
  if (state) {
    const input = document.querySelector('input[data-state="' + state + '"]');
    if (input) input.checked = true;
  }
  if (rel || state) {
    userMoved = false;
    render();
  }
});
search.addEventListener("input", function() {
  const exact = exactSearch();
  selectedId = exact ? exact.id : "";
  userMoved = false;
  render();
});
document.querySelectorAll("input:not(#search)").forEach(function(input) {
  input.addEventListener("input", function() {
    userMoved = false;
    render();
  });
});
document.getElementById("fit").addEventListener("click", fitView);
document.getElementById("reset").addEventListener("click", resetView);
document.getElementById("zoomIn").addEventListener("click", function() {
  zoomAt(1.18, stage.clientWidth / 2, stage.clientHeight / 2);
});
document.getElementById("zoomOut").addEventListener("click", function() {
  zoomAt(0.85, stage.clientWidth / 2, stage.clientHeight / 2);
});
detailsToggle.addEventListener("click", function() {
  document.body.classList.toggle("details-collapsed");
  updateDetailsToggle();
});
window.addEventListener("resize", function() {
  userMoved = false;
  render();
});

if (window.matchMedia("(max-width:900px)").matches) {
  document.body.classList.add("details-collapsed");
}
updateDetailsToggle();
wirePointerControls();
setupCounts();
renderNextActions();
render();
`;
}

function scriptJson(value) {
  return JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026");
}

function escapeHtml(value) {
  return String(value || "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch]));
}

export function writeOutput(text, output) {
  if (!output) {
    process.stdout.write(text);
    return;
  }
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, text);
  console.log(output);
}
