import childProcess from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const ISSUE_URL_RE = /^https:\/\/github\.com\/([^/]+)\/([^/]+)\/issues\/(\d+)(?:[/?#].*)?$/;

export function parseIssueUrl(url) {
  const match = String(url || "").match(ISSUE_URL_RE);
  if (!match) {
    throw new Error(`Unsupported GitHub issue URL: ${url}`);
  }
  return {
    owner: match[1],
    repo: match[2],
    number: Number(match[3]),
    fullName: `${match[1]}/${match[2]}`,
  };
}

function cursorFile(config, target) {
  return path.join(config.stateDir, "github-cursors", `${target.owner}-${target.repo}-issue-${target.number}.json`);
}

function readCursor(config, target) {
  const file = cursorFile(config, target);
  if (!fs.existsSync(file)) return { file };
  return { file, ...JSON.parse(fs.readFileSync(file, "utf8")) };
}

function writeCursor(config, target, cursor) {
  const file = cursorFile(config, target);
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  fs.writeFileSync(file, `${JSON.stringify({ ...cursor, file: undefined }, null, 2)}\n`);
  return file;
}

function runGh(args, options = {}) {
  const result = childProcess.spawnSync("gh", args, {
    encoding: "utf8",
    shell: false,
  });
  if (result.status !== 0) {
    if (options.allowNotModified && /HTTP 304/.test(`${result.stderr}\n${result.stdout}`)) {
      return { notModified: true, stdout: result.stdout, stderr: result.stderr };
    }
    const message = (result.stderr || result.stdout || result.error?.message || "gh api failed").trim();
    throw new Error(message);
  }
  return result.stdout;
}

function splitIncludeResponse(raw) {
  const normalized = String(raw || "").replace(/\r\n/g, "\n");
  const boundary = normalized.lastIndexOf("\n\n");
  if (boundary === -1) {
    return { headers: "", body: normalized };
  }
  return {
    headers: normalized.slice(0, boundary),
    body: normalized.slice(boundary + 2),
  };
}

function headerValue(headers, name) {
  const wanted = name.toLowerCase();
  for (const line of headers.split("\n")) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    if (line.slice(0, idx).trim().toLowerCase() === wanted) {
      return line.slice(idx + 1).trim();
    }
  }
  return "";
}

function statusCode(headers) {
  const match = headers.match(/^HTTP\/\S+\s+(\d+)/m);
  return match ? Number(match[1]) : 0;
}

function hashJson(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function fetchIssueData(config, target, cursor, forceFetch = false) {
  const endpoint = `repos/${target.owner}/${target.repo}/issues/${target.number}`;
  const args = ["api", "--include", endpoint];
  if (cursor.etag && !config.forceFetch && !forceFetch) {
    args.push("-H", `If-None-Match: ${cursor.etag}`);
  }
  const response = runGh(args, { allowNotModified: true });
  if (response?.notModified) {
    return { data: null, etag: cursor.etag || "", status: 304, notModified: true };
  }

  const { headers, body } = splitIncludeResponse(response);
  const status = statusCode(headers);
  const etag = headerValue(headers, "etag") || cursor.etag || "";
  if (status === 304) {
    return { data: null, etag, status, notModified: true };
  }
  return { data: JSON.parse(body), etag, status, notModified: false };
}

function normalizeFetchedComments(comments) {
  return comments.map((comment) => ({
    id: String(comment.node_id || comment.id || ""),
    body: comment.body || "",
    author: { login: comment.user?.login || "" },
    html_url: comment.html_url || "",
    created_at: comment.created_at || "",
    updated_at: comment.updated_at || comment.created_at || "",
  }));
}

function commandRelevantComments(config, comments) {
  const marker = config.daemon.statusCommentMarker || "";
  const expectedLogin = config.daemon.expectedLogin || "";
  return comments.filter((comment) => {
    if (!String(comment.body || "").trim()) return false;
    if (marker && String(comment.body || "").includes(marker)) return false;
    if (expectedLogin && comment.author?.login !== expectedLogin) return false;
    return true;
  });
}

function commentHash(config, comments) {
  return hashJson(commandRelevantComments(config, comments).map((comment) => ({
    id: comment.id,
    body: comment.body,
    author: comment.author?.login || "",
    updated_at: comment.updated_at,
  })));
}

function listComments(target) {
  const endpoint = `repos/${target.owner}/${target.repo}/issues/${target.number}/comments?per_page=100`;
  return JSON.parse(runGh(["api", endpoint, "--paginate"]));
}

export function fetchIssue(config, issueUrl) {
  const target = parseIssueUrl(issueUrl);
  const cursor = readCursor(config, target);
  let issueResponse = fetchIssueData(config, target, cursor);
  const comments = normalizeFetchedComments(listComments(target));
  const commentsHash = commentHash(config, comments);
  const polledAt = new Date().toISOString();

  if (issueResponse.notModified && commentsHash === cursor.commentHash) {
    const cursorFilePath = writeCursor(config, target, { ...cursor, polledAt, status: 304, commentHash: commentsHash });
    return { target, cursor: { ...cursor, file: cursorFilePath, polledAt, status: 304, commentHash: commentsHash }, issue: null, notModified: true };
  }

  if (issueResponse.notModified) {
    issueResponse = fetchIssueData(config, target, cursor, true);
  }

  const data = issueResponse.data;
  const cursorFilePath = writeCursor(config, target, {
    etag: issueResponse.etag,
    commentHash: commentsHash,
    polledAt,
    status: issueResponse.status,
    issueHashSeed: {
      number: data.number,
      title: data.title,
      body: data.body,
      repository: target.fullName,
      commentHash: commentsHash,
    },
  });
  return {
    target,
    cursor: { file: cursorFilePath, etag: issueResponse.etag, commentHash: commentsHash, polledAt, status: issueResponse.status },
    issue: {
      id: data.node_id || String(data.id || ""),
      number: data.number,
      title: data.title || "",
      body: data.body || "",
      repository: { full_name: target.fullName },
      author: { login: data.user?.login || "" },
      labels: (data.labels || []).map((label) => label.name || label),
      html_url: data.html_url || issueUrl,
      comments,
    },
    notModified: false,
  };
}
