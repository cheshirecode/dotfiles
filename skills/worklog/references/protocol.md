# Worklog protocol quick reference

Read this file only when the selected mode requires task creation or direct task-file editing. The mode file remains authoritative for its execution order; `_worklog/AGENTS.md` remains authoritative for protocol edge cases.

## Slugs

- Grammar: `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. Linear ID known → `eng-<N>-<desc>`. Else bare `<desc>`. No `wip-`.
- Rename: `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>`. Cross-task rewrites: `"$WORKLOG_BIN/refactor.sh" <new> --rename=<old>`.

## Status FSM

- Linear: `draft → in-progress → in-review → shipping → archived`.
- Side: `blocked` — `next_action` MUST start with `Waiting on`.
- Flip via `"$WORKLOG_BIN/checkpoint.sh" <slug> --status=X`. Never edit frontmatter `status:` alongside a separate `Worklog-Status:` trailer.
- `--status=archived` is rejected by checkpoint — use `"$WORKLOG_BIN/archive.sh" <slug> --reason=<shipped|declined|superseded|abandoned|merged|obsolete>`.

## Editing rules

- Edit only `$WORKLOG_REPO/people/$LDAP/`. Other namespaces read-only.
- Never `git rebase` / `git pull --rebase` / force-push during normal sync. Maintenance ops (`$WORKLOG_BIN/log-compact.sh`, `$WORKLOG_BIN/cache-purge.sh`) are the carve-out — see AGENTS.md.
- Prior-art grep before infra surfaces: `"$WORKLOG_BIN/related-search.sh" <keyword>`.

## Search ladder

`search.sh` is **line-level rg**, not NL Q&A. Climb only as far as needed:

1. **Planted phrase** — maps use `Lookup alias for **…**`; try the human phrase first (`"mini-apps integration"`, `"worklog manager"`).
2. **Keyword / slug fragment** — tokens in filename or body (`integration-map`, `worklog-manager`).
3. **`--project=<slug>`** — list cluster members when the project slug is known.
4. **`--list` / `--json`** — narrow, then `"$WORKLOG_BIN/context.sh" <slug>`.
5. Dual-LDAP sweeps: **omit `--ldap`** (and don't pin `WORKLOG_LDAP` for that call) so all `people/*` show; pin LDAP only for writes/checkpoints.

## Integration maps

For `kind: runbook`, slug `*-integration-map`:

- **Mandatory** when a project has **≥3** distinct repos and cross-repo lookup is load-bearing.
- **Advisory** when **≥2** repos and NL search (step 1) fails dogfood.
- **Exempt:** single-repo projects.
- Every map's `## Context` MUST start with `Lookup alias for **<phrase>**`.
- No Cursor canvases / `file://` in `external_refs` (lint errors) — in-repo runbooks only.
- Deferred (do not create yet): capability-manifest map; sandwich map (oss LDAP).

## Tooling shortlist

- Save: `"$WORKLOG_BIN/checkpoint.sh" <slug>` (single) · `"$WORKLOG_BIN/checkpoint-batch.sh" < json` (atomic multi).
- Archive: `"$WORKLOG_BIN/archive.sh" <slug> --reason=<…>`.
- Safety: `"$WORKLOG_BIN/autosave.sh"` (slugless snapshot). Hooks wired by `"$WORKLOG_BIN/install-hooks.sh" --write`.
- Standup: `"$WORKLOG_BIN/status.sh" [--since=… --project=… --slug=…]`.
- Per-task pack: `"$WORKLOG_BIN/context.sh" <slug> [--for=resume|review|compact]`.
- PR reconciliation: `"$WORKLOG_BIN/reconcile-pr.sh" <slug>` compares authoritative `Worklog-PR:` trailers with live GitHub state and emits read-only JSON; repository resolution uses `pr_repos`, exact GitHub PR URLs in the task body, known repos, or local clone remotes. Keep it read-only and limited to explicit task links; do not infer stale work from direct-to-main changes or missing PR linkage.
- Slug lookup: `"$WORKLOG_BIN/slug.sh" <fragment>`.
- Search: `"$WORKLOG_BIN/search.sh" <pattern> [--active|--archive] [--kind= --status= --project= --linear= --pr= --repo= --ldap=]`; `--list` (slugs only), `--json`, `--semantic [--top=N]`.
- Graph viewer: `"$WORKLOG_BIN/worklog-manager" graph --repo "$WORKLOG_REPO" --format html --output /tmp/worklog-graph.html [--project=slug] [--match=text]`.
- Issue dispatch: `"$WORKLOG_BIN/worklog-manager" dispatch --config <instance.json> --issue <issue.json> --output /tmp/dispatch.json` writes local artifacts; `--execute` runs the planned sandbox argv only when instance config and `Worklog-Execute: sandbox` both approve it.
- Issue poll dry-run: `"$WORKLOG_BIN/worklog-manager" poll --config <instance.json> --issue-url https://github.com/<owner>/<repo>/issues/<n> --output /tmp/poll.json` requires `poll.enabled=true`, fetches through `gh api`, updates local cursor/run artifacts, records ignored learning events under `.cache/<instance>/learning/`, and posts no GitHub comments unless `--post-status` is passed.
- Watcher config audit: `"$WORKLOG_BIN/worklog-manager" validate-watchers --config <projects.json> --config <oss.json>` checks separate watcher instances for shared state/cache dirs and same-issue status-marker collisions before polling.
- Slack context preview: `"$WORKLOG_BIN/scrape-slack.sh" [--input=slack-results.json] [--format=json]` matches captured Slack threads to tasks. Dry-run by default; workspace-agnostic by resolved clone identity; no-op when Slack is unavailable.
- Multi-task project: `"$WORKLOG_BIN/project.sh" new|next|claim|release|reap|verify|list <slug>`.
- Lint: `"$WORKLOG_BIN/lint.sh" [--cross-task]`. Boundary guard for split clones: `"$WORKLOG_BIN/boundary-lint.sh"`. Composite audit: `"$WORKLOG_BIN/audit.sh" [--section=boundary]`.
- SQL: `"$WORKLOG_BIN/sql.sh" new|run|list|show <slug> <name>`.
- New data repo: `"$WORKLOG_BIN/init-new-data-repo.sh" <path> [<ldap>]` (Phase 4 — not shipped yet).

## Task format

- `kind` ∈ {bug, bugfix, cleanup, debug, design, impl, infra, investigation, ops, perf, plan, postmortem, program, project, proposal, review, runbook, spike, tooling}.
- Notion page IDs → `notion: <id>` (no dashes), NOT `external_refs:`. `init --full` matches against `notion:`.
- Cite cross-task refs in `related[]`, not just prose.
- Bare body slugs auto-wrap to `[[<slug>]]` via `"$WORKLOG_BIN/auto-slug-link.py"`. Frontmatter slugs stay bare.
- Round-trip safe: `grep -l '<slug>' people/` matches both forms.

## Commits and hooks

- `Worklog-Slug:` trailer MUST resolve to an existing task file.
- `Worklog-Status:` trailer MUST match frontmatter `status:` for that slug.
- Both are enforced by `"$WORKLOG_BIN/git-hooks/commit-msg"`. Hand-rolling status flips via trailer alone is rejected.
- Pre-commit blocks lint errors on staged task files, scrubber regressions, ruff/shellcheck errors, and secrets via `"$WORKLOG_BIN/pre-commit-scan.sh"`.
- Commit-msg blocks typo `Worklog-Slug:` and trailer-vs-frontmatter drift.
- Post-commit advisory (TTL 1h): cross-task lint warnings, retro prompt on archive.
- Bypass any hook (one-shot, last-resort): `WORKLOG_NO_HOOK=1 git commit …`.

## Sessions

- Multi-session collision warning on `checkpoint.sh` if another session touched the same slug <5min ago. Advisory; never blocks.
- Resume kernels live at `.cache/compact-kernels.{md,json}`. Preamble emits a top-15 roster from `.json`; read the `.md` (~95KB) only on demand for full detail.
