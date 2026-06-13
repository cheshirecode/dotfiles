import fs from "node:fs";
import path from "node:path";

export const GRAPH_SCHEMA_VERSION = "worklog.graph.v1";

const FRONTMATTER_RE = /^---\n([\s\S]*?)\n---\n/;
const RELATION_FIELDS = ["reopens", "supersedes", "superseded_by"];
const REQUIRED_FIELDS = ["slug", "status", "kind", "project", "last_updated", "next_action"];

function diagnostic(level, code, message, extra = {}) {
  return { level, code, message, ...extra };
}

function unquote(value) {
  const trimmed = String(value || "").trim();
  if ((trimmed.startsWith("\"") && trimmed.endsWith("\"")) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseInlineArray(value) {
  const trimmed = value.trim();
  if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) return null;
  const body = trimmed.slice(1, -1).trim();
  if (!body) return [];
  return body.split(",").map((item) => unquote(item.trim())).filter(Boolean);
}

function parseScalar(value) {
  const inlineArray = parseInlineArray(value);
  if (inlineArray) return inlineArray;
  return unquote(value);
}

function parseKeyValue(text) {
  const match = text.match(/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/);
  if (!match) return null;
  return [match[1], parseScalar(match[2])];
}

function parseBlock(lines) {
  const items = [];
  let current = null;
  const pushCurrent = () => {
    if (current !== null) items.push(current);
    current = null;
  };

  for (const line of lines) {
    const itemMatch = line.match(/^\s*-\s*(.*)$/);
    if (itemMatch) {
      pushCurrent();
      const rest = itemMatch[1].trim();
      const kv = parseKeyValue(rest);
      current = kv ? { [kv[0]]: kv[1] } : parseScalar(rest);
      continue;
    }

    const kv = parseKeyValue(line.trim());
    if (kv && current && typeof current === "object" && !Array.isArray(current)) {
      current[kv[0]] = kv[1];
    }
  }

  pushCurrent();
  return items;
}

export function parseFrontmatter(text) {
  const match = FRONTMATTER_RE.exec(text);
  if (!match) return null;
  const lines = match[1].split(/\r?\n/);
  const out = {};

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim() || /^\s/.test(line) || line.trim().startsWith("- ")) continue;
    const kv = parseKeyValue(line);
    if (!kv) continue;
    const [key, value] = kv;
    if (value !== "") {
      out[key] = value;
      continue;
    }

    const block = [];
    while (i + 1 < lines.length && (lines[i + 1].trim() === "" || /^\s/.test(lines[i + 1]) || lines[i + 1].trim().startsWith("- "))) {
      i += 1;
      if (lines[i].trim()) block.push(lines[i]);
    }
    out[key] = parseBlock(block);
  }
  return out;
}

function listMarkdownFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((name) => name.endsWith(".md"))
    .sort()
    .map((name) => path.join(dir, name));
}

function addEdge(edges, source, target, relation, note = "", file = "") {
  if (!source || !target || source === target) return;
  const edge = {
    id: `${source}->${target}:${relation}:${edges.length}`,
    source,
    target,
    relation,
    note,
    file,
  };
  const sameEdge = edges.some((existing) => (
    existing.source === edge.source
    && existing.target === edge.target
    && existing.relation === edge.relation
    && existing.note === edge.note
  ));
  if (!sameEdge) edges.push(edge);
}

function normalizeRepos(repos) {
  return Array.isArray(repos) ? repos.map(String).filter(Boolean).sort() : [];
}

function stringList(value) {
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (value) return [String(value)];
  return [];
}

function buildTaskNode(config, ldap, state, file, fm, diagnostics) {
  const fallbackSlug = path.basename(file, ".md");
  const relativeFile = path.relative(config.worklogRepo, file);
  if (!fm) {
    diagnostics.push(diagnostic("error", "frontmatter.missing", "Task file is missing YAML frontmatter.", { file: relativeFile }));
    return null;
  }

  const slug = String(fm.slug || fallbackSlug);
  if (!fm.slug) {
    diagnostics.push(diagnostic("warning", "slug.missing", "Task file is missing slug; filename was used.", { file: relativeFile, slug }));
  } else if (slug !== fallbackSlug) {
    diagnostics.push(diagnostic("warning", "slug.filename_mismatch", "Task slug does not match filename.", { file: relativeFile, slug, expected: fallbackSlug }));
  }

  for (const field of REQUIRED_FIELDS) {
    if (!fm[field]) {
      diagnostics.push(diagnostic("warning", "frontmatter.required_missing", `Task is missing required frontmatter field '${field}'.`, { file: relativeFile, slug, field }));
    }
  }

  return {
    id: slug,
    type: "task",
    slug,
    label: slug,
    ldap,
    state,
    status: String(fm.status || ""),
    kind: String(fm.kind || ""),
    project: String(fm.project || ""),
    repos: normalizeRepos(fm.repos),
    file: relativeFile,
    synthetic: false,
    frontmatter: fm,
  };
}

function addProjectNode(nodesById, project) {
  const projectId = `project:${project}`;
  if (!nodesById.has(projectId)) {
    nodesById.set(projectId, {
      id: projectId,
      type: "project",
      slug: project,
      label: project,
      ldap: "",
      state: "project",
      status: "project",
      kind: "project",
      project,
      repos: [],
      file: "",
      synthetic: true,
    });
  }
  return projectId;
}

function resolveEdges(edges, nodesById, diagnostics) {
  for (const edge of edges) {
    edge.resolved = nodesById.has(edge.source) && nodesById.has(edge.target);
    if (!edge.resolved) {
      diagnostics.push(diagnostic("warning", "edge.unresolved", "Relation edge references a missing node.", {
        file: edge.file,
        source: edge.source,
        target: edge.target,
        relation: edge.relation,
      }));
    }
  }
}

function compactGraphFilter(config) {
  const projects = [...new Set((config.graphFilter?.projects || []).map(String).filter(Boolean))];
  const matches = [...new Set((config.graphFilter?.matches || []).map(String).filter(Boolean))];
  return { projects, matches };
}

function graphFilterEnabled(filter) {
  return filter.projects.length > 0 || filter.matches.length > 0;
}

function nodeHaystack(node) {
  return [
    node.id,
    node.slug,
    node.label,
    node.status,
    node.kind,
    node.project,
    node.file,
    ...(node.repos || []),
  ].join(" ").toLowerCase();
}

function filterDiagnostics(diagnostics, nodes, enabled) {
  if (!enabled) return diagnostics;
  const ids = new Set(nodes.map((node) => node.id));
  const files = new Set(nodes.map((node) => node.file).filter(Boolean));
  return diagnostics.filter((item) => (
    (item.slug && ids.has(item.slug))
    || (item.file && files.has(item.file))
    || (item.source && ids.has(item.source))
    || (item.target && ids.has(item.target))
  ));
}

function filterGraph(config, nodes, edges) {
  const filter = compactGraphFilter(config);
  const enabled = graphFilterEnabled(filter);
  if (!enabled) return { enabled, filter, nodes, edges };

  const projects = new Set(filter.projects);
  const matches = filter.matches.map((value) => value.toLowerCase());
  const keepIds = new Set();

  for (const node of nodes) {
    if (projects.has(node.project) || projects.has(node.slug) || projects.has(node.id.replace(/^project:/, ""))) {
      keepIds.add(node.id);
      continue;
    }
    const haystack = nodeHaystack(node);
    if (matches.some((match) => haystack.includes(match))) keepIds.add(node.id);
  }

  const seedIds = new Set(keepIds);
  for (const edge of edges) {
    if (seedIds.has(edge.source)) keepIds.add(edge.target);
    if (seedIds.has(edge.target)) keepIds.add(edge.source);
  }

  const filteredNodes = nodes.filter((node) => keepIds.has(node.id));
  const filteredEdges = edges.filter((edge) => keepIds.has(edge.source) && keepIds.has(edge.target));
  return { enabled, filter, nodes: filteredNodes, edges: filteredEdges };
}

function filterActiveOnly(nodes, edges, enabled) {
  if (!enabled) return { nodes, edges };
  const keepIds = new Set(nodes
    .filter((node) => node.state === "active" || node.state === "project")
    .map((node) => node.id));
  return {
    nodes: nodes.filter((node) => keepIds.has(node.id)),
    edges: edges.filter((edge) => keepIds.has(edge.source) && keepIds.has(edge.target)),
  };
}

export function extractGraph(config) {
  const diagnostics = [];
  const peopleDir = path.join(config.worklogRepo, "people");
  if (!fs.existsSync(peopleDir)) {
    throw new Error(`${config.worklogRepo} does not look like a worklog repo: missing people/`);
  }

  const nodesById = new Map();
  const taskFiles = [];
  for (const ldap of fs.readdirSync(peopleDir).sort()) {
    const ldapDir = path.join(peopleDir, ldap);
    if (!fs.statSync(ldapDir).isDirectory()) continue;
    const states = ["active", "archive"];
    for (const state of states) {
      for (const file of listMarkdownFiles(path.join(ldapDir, state))) {
        taskFiles.push({ ldap, state, file });
      }
    }
  }

  for (const entry of taskFiles) {
    const text = fs.readFileSync(entry.file, "utf8");
    const fm = parseFrontmatter(text);
    const node = buildTaskNode(config, entry.ldap, entry.state, entry.file, fm, diagnostics);
    if (!node) continue;
    if (nodesById.has(node.id)) {
      diagnostics.push(diagnostic("error", "slug.duplicate", "Duplicate task slug found; first task wins.", { file: node.file, slug: node.slug }));
      continue;
    }
    nodesById.set(node.id, node);
  }

  const edges = [];
  for (const task of nodesById.values()) {
    if (task.type !== "task") continue;
    const fm = task.frontmatter;
    addEdge(edges, String(fm.parent_slug || ""), task.id, "parent", "", task.file);

    for (const related of Array.isArray(fm.related) ? fm.related : []) {
      if (related && typeof related === "object") {
        addEdge(edges, task.id, String(related.slug || ""), "related", String(related.note || ""), task.file);
      }
    }

    for (const field of RELATION_FIELDS) {
      addEdge(edges, task.id, String(fm[field] || ""), field, "", task.file);
    }

    for (const item of Array.isArray(fm.tasks) ? fm.tasks : []) {
      if (!item || typeof item !== "object" || !item.slug) continue;
      for (const dependency of stringList(item.depends_on)) {
        addEdge(edges, dependency, String(item.slug), "depends_on", `declared by ${task.id}`, task.file);
      }
    }

    const project = String(fm.project || "");
    if (project && project !== "none" && project !== task.id && project !== fm.parent_slug) {
      const projectId = nodesById.has(project) ? project : addProjectNode(nodesById, project);
      addEdge(edges, projectId, task.id, "project", "", task.file);
    }
  }

  resolveEdges(edges, nodesById, diagnostics);
  const sourceNodes = [...nodesById.values()].sort((a, b) => `${a.state}:${a.slug}`.localeCompare(`${b.state}:${b.slug}`));
  const sourceEdges = edges.sort((a, b) => `${a.source}:${a.target}:${a.relation}`.localeCompare(`${b.source}:${b.target}:${b.relation}`));
  const activeFiltered = filterActiveOnly(sourceNodes, sourceEdges, config.activeOnly);
  const filtered = filterGraph(config, activeFiltered.nodes, activeFiltered.edges);
  const filteredDiagnostics = filterDiagnostics(diagnostics, filtered.nodes, filtered.enabled || config.activeOnly);

  return {
    schemaVersion: GRAPH_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    instance: {
      name: config.instance,
      configPath: config.configPath,
      roots: {
        worklogRepo: config.worklogRepo,
        stateDir: config.stateDir,
        cacheDir: config.cacheDir,
      },
      github: config.github,
      sandbox: config.sandbox,
      poll: config.poll,
      filter: filtered.filter,
    },
    summary: {
      taskFileCount: taskFiles.length,
      sourceNodeCount: sourceNodes.length,
      sourceEdgeCount: sourceEdges.length,
      nodeCount: filtered.nodes.length,
      edgeCount: filtered.edges.length,
      sourceDiagnosticCount: diagnostics.length,
      diagnosticCount: filteredDiagnostics.length,
      unresolvedEdgeCount: filteredDiagnostics.filter((item) => item.code === "edge.unresolved").length,
    },
    nodes: filtered.nodes,
    edges: filtered.edges,
    diagnostics: filteredDiagnostics,
  };
}
