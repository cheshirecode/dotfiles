import crypto from "node:crypto";
import fs from "node:fs";

const SLUG_RE = /^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$/;
const COMMAND_RE = /^(ask|plan|do|agent)$/;
const EXECUTE_RE = /^(sandbox)$/;

export function readIssue(file) {
  return normalizeIssue(JSON.parse(fs.readFileSync(file, "utf8")));
}

export function normalizeIssue(raw) {
  return {
    id: raw.id || "",
    number: Number(raw.number || 0),
    title: String(raw.title || ""),
    body: String(raw.body || ""),
    repository: String(raw.repository?.full_name || raw.repository || ""),
    author: String(raw.author?.login || raw.user?.login || raw.author || ""),
    labels: (raw.labels || []).map((label) => String(label.name || label)).sort(),
    htmlUrl: String(raw.html_url || raw.htmlUrl || ""),
    comments: (raw.comments || []).map(normalizeComment).sort(compareComments),
  };
}

export function issueFingerprint(issue) {
  const stable = JSON.stringify({
    number: issue.number,
    title: issue.title,
    body: issue.body,
    repository: issue.repository,
    comments: (issue.comments || []).map((comment) => ({
      id: comment.id,
      body: comment.body,
      author: comment.author,
      updatedAt: comment.updatedAt,
    })),
  });
  return crypto.createHash("sha256").update(stable).digest("hex");
}

function normalizeComment(raw) {
  return {
    id: String(raw.id || raw.node_id || ""),
    body: String(raw.body || ""),
    author: String(raw.author?.login || raw.user?.login || raw.author || ""),
    htmlUrl: String(raw.html_url || raw.htmlUrl || ""),
    createdAt: String(raw.created_at || raw.createdAt || ""),
    updatedAt: String(raw.updated_at || raw.updatedAt || raw.created_at || raw.createdAt || ""),
  };
}

function compareComments(a, b) {
  const aTime = Date.parse(a.updatedAt || a.createdAt || "") || 0;
  const bTime = Date.parse(b.updatedAt || b.createdAt || "") || 0;
  if (aTime !== bTime) return aTime - bTime;
  return String(a.id).localeCompare(String(b.id));
}

function matchTrailer(body, name) {
  const re = new RegExp(`^${name}:\\s*(.+?)\\s*$`, "im");
  const match = body.match(re);
  return match ? match[1].trim() : "";
}

function matchSlashCommand(body) {
  const match = body.match(/^\/(ask|plan|do|agent)\b/im);
  return match ? match[1].toLowerCase() : "";
}

function taskSlugs(graph) {
  return (graph?.nodes || [])
    .filter((node) => node.type === "task" && node.slug)
    .map((node) => String(node.slug))
    .sort();
}

function escapeRe(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function findMentionedSlugs(text, slugs) {
  const hits = [];
  for (const slug of slugs) {
    const slugPattern = `(^|[^a-z0-9])${escapeRe(slug)}([^a-z0-9]|$)`;
    const phrasePattern = `(^|[^a-z0-9])${slug.split("-").map(escapeRe).join("[\\s_/-]+")}([^a-z0-9]|$)`;
    if (new RegExp(slugPattern, "i").test(text) || new RegExp(phrasePattern, "i").test(text)) {
      hits.push(slug);
    }
  }
  return hits;
}

function inferSlug(text, graph, config) {
  const slugs = taskSlugs(graph);
  const mentioned = findMentionedSlugs(text, slugs);
  if (mentioned.length === 1) return { slug: mentioned[0], source: "natural-language" };
  if (mentioned.length > 1) {
    return {
      slug: "",
      source: "",
      error: {
        code: "slug.ambiguous",
        message: `Issue text matched multiple worklog slugs: ${mentioned.join(", ")}.`,
      },
    };
  }

  const defaultSlug = String(config?.daemon?.defaultSlug || "");
  if (!defaultSlug) return { slug: "", source: "" };
  if (!slugs.includes(defaultSlug)) {
    return {
      slug: "",
      source: "",
      error: {
        code: "slug.default_not_found",
        message: `Configured daemon.defaultSlug '${defaultSlug}' is not present in this instance graph.`,
      },
    };
  }
  return { slug: defaultSlug, source: "daemon.defaultSlug" };
}

function inferCommand(text) {
  const normalized = String(text || "").toLowerCase();
  const candidates = [];
  const add = (command) => {
    if (!candidates.includes(command)) candidates.push(command);
  };

  if (/\b(dry[-\s]?run|preview|plan|non[-\s]?mutating|no[-\s]?mutation)\b/.test(normalized)
    || /\bdo not\s+(execute|run|mutate|apply)\b/.test(normalized)
    || /\bwithout\s+(executing|running|mutating|applying)\b/.test(normalized)) {
    add("plan");
  }
  if (/\b(ask|question|answer)\b/.test(normalized)) add("ask");
  if (/\b(agent|autonomous)\b/.test(normalized)) add("agent");

  const executableText = normalized.replace(/\bdry[-\s]?run\b/g, "");
  const negatesExecution = /\b(do not|don't|dont|without|no)\s+(execute|run|mutate|apply|executing|running|mutating|applying)\b/.test(normalized)
    || /\bnon[-\s]?mutating\b/.test(normalized);
  if (!negatesExecution && !candidates.includes("agent") && /\b(do|execute|run|apply|implement)\b/.test(executableText)) add("do");

  if (candidates.length === 1) return { command: candidates[0], source: "natural-language" };
  if (candidates.length > 1) {
    return {
      command: "",
      source: "",
      error: {
        code: "command.ambiguous",
        message: `Issue text matched multiple worklog commands: ${candidates.join(", ")}.`,
      },
    };
  }
  return { command: "", source: "" };
}

function inferExecution(text, confirmation) {
  const target = String(confirmation || "").toLowerCase();
  if (!target) return { requested: false, target: "", source: "" };

  const normalized = String(text || "").toLowerCase();
  const targetRe = new RegExp(`\\b${escapeRe(target)}\\b`);
  if (!targetRe.test(normalized)) return { requested: false, target: "", source: "" };

  const negatesExecution = /\b(do not|don't|dont|without|no|not)\s+(sandbox\s+)?(execute|run|mutate|apply|executing|running|mutating|applying|execution)\b/.test(normalized)
    || /\bwithout\b[^.!\n]{0,80}\bsandbox\b/.test(normalized)
    || /\bno\s+sandbox\b/.test(normalized)
    || /\bnon[-\s]?mutating\b/.test(normalized)
    || /\bdry[-\s]?run\b/.test(normalized);
  if (negatesExecution) return { requested: false, target: "", source: "" };

  const asksForExecution = /\b(execute|execution|run|running|run[-\s]?headless|smoke)\b/.test(normalized);
  if (!asksForExecution) return { requested: false, target: "", source: "" };

  return { requested: true, target, source: "natural-language" };
}

export function parseIssueIntent(issue) {
  const slug = matchTrailer(issue.body, "Worklog-Slug");
  const trailerCommand = matchTrailer(issue.body, "Worklog-Command");
  const slashCommand = matchSlashCommand(issue.body);
  const command = (trailerCommand || slashCommand).toLowerCase();
  const executeTarget = matchTrailer(issue.body, "Worklog-Execute").toLowerCase();
  const prompt = issue.body
    .replace(/^Worklog-Slug:\s*.+?\s*$/gim, "")
    .replace(/^Worklog-Command:\s*.+?\s*$/gim, "")
    .replace(/^Worklog-Execute:\s*.+?\s*$/gim, "")
    .replace(/^\/(ask|plan|do|agent)\b.*$/gim, "")
    .trim();
  return {
    slug,
    command,
    prompt,
    execute: {
      requested: Boolean(executeTarget),
      target: executeTarget,
      source: executeTarget ? "trailer" : "",
    },
    sources: {
      slug: slug ? "trailer" : "",
      command: trailerCommand ? "trailer" : slashCommand ? "slash" : "",
    },
    source: {
      type: "issue-body",
      author: issue.author,
      id: issue.id,
      htmlUrl: issue.htmlUrl,
    },
    errors: [],
  };
}

export function inferIssueIntent(issue, graph, config) {
  const source = intentSource(issue, config);
  const intent = parseIssueIntent(source.issue);
  intent.source = source.meta;
  const text = [source.includeTitle ? issue.title : "", intent.prompt].filter(Boolean).join("\n");

  if (!intent.slug) {
    const inferred = inferSlug(text, graph, config);
    intent.slug = inferred.slug;
    intent.sources.slug = inferred.source;
    if (inferred.error) intent.errors.push(inferred.error);
  }

  if (!intent.command) {
    const inferred = inferCommand(text);
    intent.command = inferred.command;
    intent.sources.command = inferred.source;
    if (inferred.error) intent.errors.push(inferred.error);
  }

  if (!intent.execute.requested) {
    intent.execute = inferExecution(text, config?.daemon?.execution?.confirmation);
  }

  return intent;
}

function intentSource(issue, config) {
  const marker = config?.daemon?.statusCommentMarker || "";
  const expectedLogin = config?.daemon?.expectedLogin || "";
  const comments = (issue.comments || []).filter((comment) => {
    if (!comment.body.trim()) return false;
    if (marker && comment.body.includes(marker)) return false;
    if (expectedLogin && comment.author !== expectedLogin) return false;
    return true;
  });
  const comment = comments[comments.length - 1];
  if (!comment) {
    return {
      issue,
      includeTitle: true,
      meta: {
        type: "issue-body",
        author: issue.author,
        id: issue.id,
        htmlUrl: issue.htmlUrl,
      },
    };
  }

  return {
    issue: {
      ...issue,
      id: comment.id,
      body: comment.body,
      author: comment.author,
      htmlUrl: comment.htmlUrl || issue.htmlUrl,
    },
    includeTitle: false,
    meta: {
      type: "issue-comment",
      author: comment.author,
      id: comment.id,
      htmlUrl: comment.htmlUrl,
      updatedAt: comment.updatedAt,
    },
  };
}

export function validateIntent(intent) {
  const errors = [...(intent.errors || [])];
  const hasSlugResolutionError = errors.some((error) => error.code.startsWith("slug."));
  const hasCommandResolutionError = errors.some((error) => error.code.startsWith("command."));

  if (!intent.slug && !hasSlugResolutionError) errors.push({ code: "slug.missing", message: "Issue must mention one worklog slug or the instance must set daemon.defaultSlug." });
  else if (!SLUG_RE.test(intent.slug)) errors.push({ code: "slug.invalid", message: "Worklog-Slug is not a valid worklog slug." });

  if (!intent.command && !hasCommandResolutionError) errors.push({ code: "command.missing", message: "Issue must say ask, plan, do, agent, dry-run, or use Worklog-Command: ask|plan|do|agent." });
  else if (!COMMAND_RE.test(intent.command)) errors.push({ code: "command.invalid", message: "Worklog-Command must be ask, plan, do, or agent." });

  if (intent.execute.requested && !EXECUTE_RE.test(intent.execute.target)) {
    errors.push({ code: "execution.invalid_target", message: "Worklog-Execute must be sandbox." });
  }
  return errors;
}

export function redactedIssue(issue) {
  return {
    number: issue.number,
    title: issue.title,
    repository: issue.repository,
    author: issue.author,
    labels: issue.labels,
    htmlUrl: issue.htmlUrl,
    commentCount: issue.comments.length,
  };
}
