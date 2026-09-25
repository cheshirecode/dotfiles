---
name: job-search
description: Source remote job postings from public boards (Greenhouse boards, HN Who-is-hiring, RemoteOK, LinkedIn via the browser harness, direct URLs), filter them for a target market, and persist the pool into a `_worklog` program. Mechanical sourcing only; tailoring and application packages belong to `job-application`.
---

# job-search

Scripted sourcing of remote job postings into a filtered, persistent pool.
This skill owns the mechanical parts: fetch, filter, render, append. Judgment
parts (fit assessment, tailoring, applying) are out of scope — hand a target
to the `job-application` skill once shortlisted.

## When to use

- User asks to find remote jobs in a market (e.g. Canada) from named boards or companies.
- A `_worklog` job-search program exists (or should be created) as the pool hub.

## Source ladder — cheapest first

1. **Public boards via HTTP** (no browser): `greenhouse-board.py`, `hn-wih.py`,
   `remoteok.py`. Run these before any browser work.
2. **Direct posting URLs**: `jd-pull.py <url>` (shared with `job-application`).
   Exit 3 means JS-only shell — escalate that URL to the browser harness.
3. **LinkedIn via the browser harness** (background tabs only): run
   `linkedin-jobs.py` under `browser-use`. Two modes:
   `LJ_MODE=keyword` (keyword + location search) and `LJ_MODE=company`
   (a company slug's `/jobs/` page). LinkedIn's AI search may rewrite filter
   URLs and drop `f_WT=2` — capture the remote flag per posting from its
   location text, never from the URL.

## Invocation

```bash
# HTTP sources (stdlib only)
skills/job-search/bin/greenhouse-board.py instacart --country canada --remote-only
skills/job-search/bin/hn-wih.sh                     # latest Who-is-hiring month
skills/job-search/bin/remoteok.py --country canada

# LinkedIn (needs the browser-use daemon; BU_CDP_URL or local Chrome)
BU_CDP_URL=http://<host>:9223 browser-use run skills/job-search/bin/linkedin-jobs.py

# JD text for a direct URL (also: skills/job-application/bin/jd-pull.py)
skills/job-search/bin/jd-pull.py https://boards.greenhouse.io/example/jobs/123

# Persist rendered rows into the program's ## Pool section
skills/job-search/bin/pool-append.py --file people/oss/active/<program>.md \
  --source "Greenhouse instacart 2026-09-25" --rows-file rows.md
```

`linkedin-jobs.py` configuration (env): `LJ_MODE=keyword|company`,
`LJ_QUERY`, `LJ_LOCATION` (default Canada), `LJ_COMPANY` (slug),
`LJ_LIMIT` (default 8). It prints markdown rows; add `LJ_FORMAT=json` for rows
as JSON. It never activates a tab except for the one retry the harness skill
prescribes when a background scroll times out, and never types, clicks, or
applies.

## Discipline

- Read-only: fetch and extract only. No auto-apply, no form submission, no
  third-party posting. Login walls stop and ask the user.
- Posting facts rot: every persisted row carries its gather date; re-verify a
  link the day an application goes out (invariant echoed in the pool program).
- One tab per site/task; reuse a matching tab before opening a new one.

## Persistence

The pool lives in a `_worklog` program task (kind `program`, parent of any
per-target application tasks). `pool-append.py` inserts a dated `###` block
under `## Pool`; per-target tasks are created with
`"$WORKLOG_BIN/project.sh" add-child <program-slug> <child-slug> --kind=plan
--title=...` so the stub and the parent's `tasks:` entry land in one commit.
Commit subjects follow `_worklog/AGENTS.md`: `<slug>: <what changed>` with
`Worklog-Kind:` on creates.
