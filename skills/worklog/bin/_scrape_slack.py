#!/usr/bin/env python3
"""Match captured Slack results to worklog tasks without writing transcripts."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SECRET_RE = re.compile(
    r"(xox[a-zA-Z]-[A-Za-z0-9-]+|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]+)"
)
LINEAR_RE = re.compile(r"\bENG-\d+\b", re.I)
PR_RE = re.compile(r"(?:\bPR\s*#|\B#)(\d{2,6})\b", re.I)

SLACK_API_BASE = "https://slack.com/api"


@dataclass
class Task:
    slug: str
    path: Path
    ldap: str
    state: str
    status: str = ""
    project: str = ""
    linear: str = ""
    prs: set[str] = field(default_factory=set)
    slack_urls: set[str] = field(default_factory=set)
    body: str = ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Preview Slack-derived worklog task enrichments.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--input", help="captured Slack result JSON; '-' for stdin")
    parser.add_argument("--format", choices=["json", "markdown"], default="json")
    parser.add_argument("--ldap", help="override resolved worklog namespace")
    parser.add_argument("--threshold", type=int, default=80)
    parser.add_argument("--apply", action="store_true", help="reserved mutation gate; refuses writes for now")
    parser.add_argument("--include-dms", action="store_true")
    parser.add_argument("--include-mpims", action="store_true")
    parser.add_argument("--no-env", action="store_true", help="disable env/API Slack provider even if SLACK_BOT_TOKEN is set")
    return parser.parse_args()


def run_text(argv: list[str], cwd: Path | None = None) -> str:
    return subprocess.check_output(argv, cwd=str(cwd) if cwd else None, text=True).strip()


def resolve_repo() -> Path | None:
    env = os.environ.get("WORKLOG_REPO")
    if env:
        repo = Path(env).expanduser().resolve()
        if (repo / ".git").exists() or (repo / "people").exists():
            return repo
    try:
        top = run_text(["git", "rev-parse", "--show-toplevel"])
    except Exception:
        return None
    repo = Path(top).resolve()
    if (repo / "people").exists():
        return repo
    return None


def resolve_ldap(repo: Path | None, override: str | None) -> str:
    if override:
        return override
    explicit = os.environ.get("WORKLOG_LDAP") or os.environ.get("WORKLOG_NS")
    if explicit:
        return explicit
    try:
        email = run_text(["git", "config", "user.email"], cwd=repo)
    except Exception:
        email = ""
    if email:
        return re.sub(r"^[0-9]+\+", "", email).split("@", 1)[0]
    return os.environ.get("USER") or "user"


def split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}, text
    raw = text[4:end].splitlines()
    data: dict[str, str] = {}
    for line in raw:
        if not line or line.startswith(" ") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data, text[end + 5 :]


def parse_prs(value: str, body: str) -> set[str]:
    prs = {m.group(1) for m in PR_RE.finditer(body)}
    for number in re.findall(r"\d+", value or ""):
        prs.add(number)
    return prs


def parse_slack_urls(text: str) -> set[str]:
    return set(re.findall(r"https://[^\s)>\"]+\.slack\.com/[^\s)>\"]+", text))


def load_tasks(repo: Path) -> list[Task]:
    tasks: list[Task] = []
    for state in ("active", "archive"):
        for path in sorted((repo / "people").glob(f"*/{state}/*.md")):
            text = path.read_text(encoding="utf-8")
            fm, body = split_frontmatter(text)
            slug = fm.get("slug") or path.stem
            tasks.append(
                Task(
                    slug=slug,
                    path=path,
                    ldap=path.parts[-3],
                    state=state,
                    status=fm.get("status", ""),
                    project=fm.get("project", ""),
                    linear=fm.get("linear", ""),
                    prs=parse_prs(fm.get("pr", ""), body),
                    slack_urls=parse_slack_urls(text),
                    body=body,
                )
            )
    return tasks


def read_input(path: str | None, token: str | None) -> tuple[str, dict[str, Any] | None]:
    if path:
        raw = sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")
        return "mock", json.loads(raw)
    if token:
        return "env", None
    return "disabled", None


def resolve_env_token() -> str | None:
    return os.environ.get("SLACK_BOT_TOKEN") or os.environ.get("SLACK_TOKEN")


def slack_api_call(method: str, token: str, params: dict[str, Any] | None = None, _retried: bool = False) -> dict[str, Any]:
    url = f"{SLACK_API_BASE}/{method}"
    data = urllib.parse.urlencode(params or {}).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 429 and not _retried:
            retry_after = int(e.headers.get("Retry-After", "2"))
            time.sleep(retry_after)
            return slack_api_call(method, token, params, _retried=True)
        return {"ok": False, "error": f"HTTP {e.code}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def fetch_env_results(token: str, tasks: list[Task]) -> tuple[dict[str, Any] | None, list[str]]:
    """Search Slack for active task slugs. Returns (payload, auth_limitations)."""
    auth = slack_api_call("auth.test", token)
    if not auth.get("ok"):
        return None, [f"Slack auth failed: {auth.get('error', 'unknown')}"]

    workspace = {
        "id": auth.get("team_id", "unknown"),
        "name": auth.get("team", "unknown"),
    }

    seen_permalinks: set[str] = set()
    messages: list[dict[str, Any]] = []

    active_slugs = [t.slug for t in tasks if t.state == "active"]
    for i, slug in enumerate(active_slugs):
        if i > 0:
            time.sleep(0.5)
        result = slack_api_call("search.messages", token, {"query": slug, "count": 5})
        if not result.get("ok"):
            continue
        matches = result.get("messages", {}).get("matches", [])
        for msg in matches:
            permalink = msg.get("permalink", "")
            if not permalink or permalink in seen_permalinks:
                continue
            seen_permalinks.add(permalink)
            channel = msg.get("channel", {})
            surface = "public"
            if channel.get("is_im"):
                surface = "dm"
            elif channel.get("is_mpim"):
                surface = "mpim"
            elif channel.get("is_private"):
                surface = "private"
            messages.append({
                "permalink": permalink,
                "channel": channel.get("id", ""),
                "channel_name": channel.get("name", ""),
                "ts": msg.get("ts", ""),
                "thread_ts": msg.get("thread_ts", msg.get("ts", "")),
                "surface": surface,
                "text": msg.get("text", ""),
                "summary": "",
            })

    return {"workspace": workspace, "messages": messages}, []


def flatten_messages(payload: dict[str, Any]) -> list[dict[str, Any]]:
    if isinstance(payload.get("messages"), list):
        return list(payload["messages"])
    if isinstance(payload.get("threads"), list):
        return list(payload["threads"])
    return []


def workspace_for(payload: dict[str, Any], msg: dict[str, Any]) -> dict[str, Any]:
    workspace = payload.get("workspace") or {}
    if msg.get("workspace"):
        workspace = msg["workspace"]
    return {
        "id": msg.get("workspace_id") or workspace.get("id") or "unknown",
        "name": msg.get("workspace_name") or workspace.get("name") or "unknown",
    }


def redact(text: str) -> tuple[str, bool]:
    redacted = SECRET_RE.sub("[REDACTED]", text or "")
    return redacted, redacted != (text or "")


def durable_summary(msg: dict[str, Any]) -> tuple[str, bool]:
    source = str(msg.get("summary") or msg.get("title") or "").strip()
    if not source:
        source = "Slack context captured; review source permalink."
    source, changed = redact(source)
    source = re.sub(r"\s+", " ", source)
    if len(source) > 220:
        source = source[:217].rstrip() + "..."
    return source, changed


def slug_tokens(value: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", value.lower()) if len(t) >= 3 and not t.isdigit()}


def score_task(task: Task, text: str, permalink: str) -> tuple[int, list[str]]:
    haystack = text.lower()
    reasons: list[str] = []
    score = 0
    if permalink and permalink in task.slack_urls:
        return 1000, ["duplicate_permalink"]
    if re.search(rf"(?<![a-z0-9-]){re.escape(task.slug.lower())}(?![a-z0-9-])", haystack):
        score += 100
        reasons.append("explicit_slug")
    linears = {m.upper() for m in LINEAR_RE.findall(text)}
    if task.linear and task.linear.upper() in linears:
        score += 80
        reasons.append("linear_token")
    prs = {m.group(1) for m in PR_RE.finditer(text)}
    if prs and task.prs.intersection(prs):
        score += 80
        reasons.append("pr_token")
    if task.project and task.project != "none" and task.project.lower() in haystack:
        score += 45
        reasons.append("project_token")
    overlap = slug_tokens(task.slug).intersection(slug_tokens(text))
    if overlap:
        score += min(35, 12 * len(overlap))
        reasons.append("title_keyword_overlap")
    return score, reasons


def build_proposals(tasks: list[Task], payload: dict[str, Any], ldap: str, threshold: int, include_dms: bool, include_mpims: bool) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    proposals: list[dict[str, Any]] = []
    searched: dict[str, dict[str, Any]] = {}
    skipped: list[dict[str, Any]] = []

    for msg in flatten_messages(payload):
        workspace = workspace_for(payload, msg)
        searched.setdefault(workspace["id"], {"id": workspace["id"], "name": workspace["name"], "messages": 0})
        surface = str(msg.get("surface") or "public").lower()
        if surface == "dm" and not include_dms:
            skipped.append({"reason": "private_surface_not_enabled", "surface": surface, "permalink": msg.get("permalink") or msg.get("url")})
            continue
        if surface == "mpim" and not include_mpims:
            skipped.append({"reason": "private_surface_not_enabled", "surface": surface, "permalink": msg.get("permalink") or msg.get("url")})
            continue
        searched[workspace["id"]]["messages"] += 1
        permalink = str(msg.get("permalink") or msg.get("url") or "")
        text = " ".join(str(msg.get(k) or "") for k in ("text", "summary", "title", "permalink", "url"))
        scored = []
        for task in tasks:
            score, reasons = score_task(task, text, permalink)
            if score > 0:
                scored.append((score, task, reasons))
        scored.sort(key=lambda item: (-item[0], item[1].slug))
        summary, was_redacted = durable_summary(msg)

        if not scored:
            proposals.append(base_proposal(msg, workspace, None, 0, [], "unmatched", "proposal_only", summary, was_redacted))
            continue

        top_score, top_task, top_reasons = scored[0]
        ties = [item for item in scored if item[0] == top_score]
        if "duplicate_permalink" in top_reasons:
            action = "duplicate_ignored"
            decision = "duplicate Slack permalink already recorded"
        elif len(ties) > 1:
            action = "proposal_only"
            decision = "ambiguous top score"
        elif top_task.state == "archive":
            action = "proposal_only"
            decision = "archived task is not revived"
        elif top_task.ldap != ldap:
            action = "proposal_only"
            decision = "peer-owned task"
        elif top_score >= threshold:
            action = "edit_candidate"
            decision = "score meets threshold"
        else:
            action = "proposal_only"
            decision = "score below threshold"
        proposal = base_proposal(msg, workspace, top_task, top_score, top_reasons, decision, action, summary, was_redacted)
        proposal["alternates"] = [
            {"slug": task.slug, "score": score, "reasons": reasons, "state": task.state, "ldap": task.ldap}
            for score, task, reasons in scored[1:4]
        ]
        proposals.append(proposal)

    coverage = {
        "searched_workspaces": list(searched.values()),
        "skipped": skipped,
        "auth_limitations": [],
    }
    return proposals, coverage


def base_proposal(
    msg: dict[str, Any],
    workspace: dict[str, Any],
    task: Task | None,
    score: int,
    reasons: list[str],
    decision: str,
    action: str,
    summary: str,
    was_redacted: bool,
) -> dict[str, Any]:
    permalink = str(msg.get("permalink") or msg.get("url") or "")
    external_ref = None
    if permalink:
        external_ref = {
            "platform": "slack",
            "url": permalink,
            "note": summary or "Slack context",
        }
    return {
        "workspace": workspace,
        "source": {
            "permalink": permalink,
            "channel": msg.get("channel") or msg.get("channel_id"),
            "channel_name": msg.get("channel_name"),
            "ts": msg.get("ts"),
            "thread_ts": msg.get("thread_ts") or msg.get("ts"),
            "surface": msg.get("surface") or "public",
        },
        "match": {
            "slug": task.slug if task else None,
            "path": str(task.path) if task else None,
            "ldap": task.ldap if task else None,
            "state": task.state if task else None,
            "score": score,
            "reasons": reasons,
            "decision": decision,
        },
        "action": action,
        "proposed": {
            "summary": summary,
            "external_refs_add": [external_ref] if external_ref and action != "duplicate_ignored" else [],
            "section": "## Notes from Slack",
        },
        "redaction": {
            "status": "redacted" if was_redacted else "clean",
        },
    }


def checkpoint_payload(proposals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    payload = []
    for proposal in proposals:
        if proposal["action"] != "edit_candidate":
            continue
        path = proposal["match"]["path"]
        payload.append(
            {
                "slug": proposal["match"]["slug"],
                "include": [path] if path else [],
                "reason": "slack-enrichment-preview",
            }
        )
    return payload


def merge_external_refs(text: str, permalink: str, summary: str) -> tuple[str, bool]:
    """Idempotently add a Slack external_refs entry to frontmatter."""
    if not text.startswith("---\n"):
        return text, False
    end = text.find("\n---\n", 4)
    if end < 0:
        return text, False
    fm = text[4:end]
    after = text[end + 5:]

    if f"url: {permalink}" in fm:
        return text, False

    entry = (
        f"  - platform: slack\n"
        f"    url: {permalink}\n"
        f"    note: {summary}\n"
    )

    m = re.search(r'^external_refs:\s*\n((?:[ \t].+\n)*)', fm, re.MULTILINE)
    if m:
        new_fm = fm[:m.end()] + entry + fm[m.end():]
    else:
        new_fm = fm.rstrip() + "\nexternal_refs:\n" + entry
    return "---\n" + new_fm + "---\n" + after, True


def merge_notes_section(text: str, permalink: str, summary: str) -> tuple[str, bool]:
    """Idempotently append a redacted bullet to ## Notes from Slack."""
    header = "## Notes from Slack"
    if permalink in text and header in text:
        section_start = text.index(header)
        section_end = _next_section_end(text, section_start + len(header))
        if permalink in text[section_start:section_end]:
            return text, False

    bullet = f"- {summary} — [source]({permalink})"
    if header not in text:
        new_text = text.rstrip() + "\n\n" + header + "\n\n" + bullet + "\n"
    else:
        start = text.index(header)
        end = _next_section_end(text, start + len(header))
        block = text[start:end].rstrip()
        new_text = text[:start] + block + "\n" + bullet + "\n" + text[end:]
    return new_text, True


def _next_section_end(text: str, from_idx: int) -> int:
    m = re.search(r'\n## ', text[from_idx:])
    return from_idx + m.start() + 1 if m else len(text)


def apply_writes(proposals: list[dict[str, Any]], ldap: str) -> list[dict[str, Any]]:
    """Mutate task files for edit_candidate proposals. Returns per-task write records."""
    records: list[dict[str, Any]] = []
    for proposal in proposals:
        if proposal["action"] != "edit_candidate":
            continue
        path_str = proposal["match"]["path"]
        slug = proposal["match"]["slug"]
        permalink = proposal["source"]["permalink"]
        summary = proposal["proposed"]["summary"]
        path = Path(path_str)
        text = path.read_text(encoding="utf-8")

        text, refs_changed = merge_external_refs(text, permalink, summary)
        text, notes_changed = merge_notes_section(text, permalink, summary)

        changed = refs_changed or notes_changed
        if changed:
            path.write_text(text, encoding="utf-8")
        records.append(
            {
                "slug": slug,
                "path": path_str,
                "permalink": permalink,
                "written": changed,
                "changes": [
                    *(["external_refs"] if refs_changed else []),
                    *(["notes_from_slack"] if notes_changed else []),
                ],
                "reason": "" if changed else "permalink already present (idempotent)",
            }
        )
    return records


def markdown_report(result: dict[str, Any]) -> str:
    lines = [
        f"scrape-slack: {result['status']}",
        f"provider: {result['provider']['type']}",
        f"identity: {result['identity']['ldap']}",
        "",
        "## Coverage",
    ]
    for ws in result["coverage"]["searched_workspaces"]:
        lines.append(f"- searched {ws['name']} ({ws['id']}): {ws['messages']} message(s)")
    if not result["coverage"]["searched_workspaces"]:
        lines.append("- no workspace searched")
    for skipped in result["coverage"]["skipped"]:
        lines.append(f"- skipped {skipped.get('surface', 'unknown')}: {skipped['reason']}")
    lines.extend(["", "## Proposals"])
    for proposal in result["proposals"]:
        slug = proposal["match"]["slug"] or "<unmatched>"
        lines.append(
            f"- {proposal['action']}: {slug} score={proposal['match']['score']} "
            f"reasons={','.join(proposal['match']['reasons']) or '-'}"
        )
    writes = result.get("writes", {})
    if writes.get("performed"):
        lines.extend(["", "## Writes"])
        for rec in writes.get("records", []):
            if rec["written"]:
                lines.append(f"- {rec['slug']}: {', '.join(rec['changes'])} ← {rec['permalink']}")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    repo = resolve_repo()
    ldap = resolve_ldap(repo, args.ldap)
    token = None if args.no_env else resolve_env_token()
    provider_type, payload = read_input(args.input, token)

    if args.apply and provider_type == "disabled":
        result = {
            "schemaVersion": "worklog.scrape-slack.v1",
            "status": "refused",
            "error": "--apply requires --input or env/API Slack provider (SLACK_BOT_TOKEN)",
            "provider": {"type": provider_type},
            "identity": {"ldap": ldap, "repo": str(repo) if repo else None},
            "writes": {"performed": False},
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 2

    if provider_type == "disabled":
        result = {
            "schemaVersion": "worklog.scrape-slack.v1",
            "status": "unavailable",
            "provider": {
                "type": "disabled",
                "reason": "no --input fixture and no env/API Slack provider configured",
            },
            "identity": {"ldap": ldap, "repo": str(repo) if repo else None},
            "coverage": {"searched_workspaces": [], "skipped": [], "auth_limitations": ["Slack provider unavailable"]},
            "proposals": [],
            "checkpoint_batch": [],
            "writes": {"performed": False},
        }
    else:
        if repo is None:
            raise SystemExit("scrape-slack: WORKLOG_REPO is unset and cwd is not a worklog repo")
        tasks = load_tasks(repo)

        auth_limitations: list[str] = []
        if provider_type == "env":
            payload, auth_limitations = fetch_env_results(token, tasks)
            if payload is None:
                result = {
                    "schemaVersion": "worklog.scrape-slack.v1",
                    "status": "unavailable",
                    "provider": {"type": "env", "reason": auth_limitations[0] if auth_limitations else "auth failed"},
                    "identity": {"ldap": ldap, "repo": str(repo)},
                    "coverage": {"searched_workspaces": [], "skipped": [], "auth_limitations": auth_limitations},
                    "proposals": [],
                    "checkpoint_batch": [],
                    "writes": {"performed": False},
                }
                if args.format == "json":
                    print(json.dumps(result, indent=2, sort_keys=True))
                else:
                    print(markdown_report(result), end="")
                return 0

        proposals, coverage = build_proposals(
            tasks,
            payload or {},
            ldap,
            args.threshold,
            args.include_dms,
            args.include_mpims,
        )
        coverage["auth_limitations"] = auth_limitations
        writes: dict[str, Any] = {"performed": False, "records": []}
        status = "preview"
        if args.apply:
            records = apply_writes(proposals, ldap)
            writes = {
                "performed": any(r["written"] for r in records),
                "records": records,
            }
            status = "applied"
        result = {
            "schemaVersion": "worklog.scrape-slack.v1",
            "status": status,
            "provider": {"type": provider_type},
            "identity": {"ldap": ldap, "repo": str(repo)},
            "coverage": coverage,
            "proposals": proposals,
            "checkpoint_batch": checkpoint_payload(proposals),
            "writes": writes,
        }

    if args.format == "json":
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(markdown_report(result), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
