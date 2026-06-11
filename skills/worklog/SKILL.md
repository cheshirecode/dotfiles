---
name: worklog
description: One skill for the shared `_worklog` repo. Eleven modes — `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `project`, `review`. Invoke as `/worklog <mode> [args]`. Bare `/worklog` or `/worklog help` prints the subcommand menu and stops. Unknown arg → show menu.
---

# worklog

Single entry point for the shared `_worklog` protocol. Canonical protocol lives in `_worklog/AGENTS.md`. This file is a **router** + **quickref**. Mode detail lives in `modes/<name>.md` and is loaded on-demand.

## Routing — first thing, before anything else

Parse the first argument. If empty, `help`, `-h`, `--help`, or unknown, print the menu verbatim and **stop** — no preamble, no tool calls, no file reads.

```
/worklog — shared cross-machine work journal

  init [--full|--light]    onboard this machine/session
  sync [<slug>] [flags]    save state (checkpoint | archive | backfill | autosave)
  status [flags]           standup summary from git log + Worklog-* trailers
  context <slug> [flags]   single-shot context pack for resume/review
  plan <task>              structured CoT/ToT/Reflexion plan for a new task
  spawn <task>             self-contained handoff prompt for a fresh session
  export                   sanitized setup prompt → /tmp/worklog-setup-<ts>.txt
  import <path>            merge an export artifact into this machine
  lint [--cross-task]      validate task files; --cross-task adds drift checks
  project <subcommand>     multi-task projects with per-task mutex (new|next|claim|release|reap|verify|list)
  review                   periodic protocol review (structure / skills / commands / perf)
  help                     this menu

flags detail: see modes/<name>.md
```

Once a known mode is parsed: run preamble (per table), read `modes/<mode>.md`, follow it.

## Mode → preamble requirement

| Mode    | Preamble | Reads AGENTS.md? | lessons.md? |
|---------|----------|------------------|-------------|
| init    | `--full` | yes              | quickref (limit=15) |
| sync    | `--full` | only if writing a new/existing task | no |
| status  | `--minimal` | no            | no |
| context | `--minimal` | no            | no |
| plan    | none     | no               | no |
| spawn   | none     | no               | no |
| export  | none     | no               | no |
| import  | none     | no               | no |
| lint    | none     | no               | no |
| project | `--minimal` (read-only subs); `--full` (mutating) | no | no |
| review  | `--full` | yes              | full |

## Paths — single source of truth

Scripts live in the dotfiles skill, NOT in the data repo:

```bash
WORKLOG_BIN="${WORKLOG_BIN:-$HOME/Documents/oss/dotfiles/skills/worklog/bin}"
WORKLOG_REPO="${WORKLOG_REPO:?per-clone .envrc must export this}"
```

Every example below uses `$WORKLOG_BIN/foo.sh` — these are the dotfiles-shipped scripts. The `WORKLOG_REPO` env var (set by each clone's `.envrc`) tells the scripts which data repo they're operating on; identity (LDAP) is resolved per-clone from `WORKLOG_LDAP` env, else git email, else `$USER`.

## Preamble — single call

```bash
cd "$WORKLOG_REPO" && "$WORKLOG_BIN/preamble.sh" [--minimal|--full]
```

Emits `LDAP=`, `PROJECTS_DIR=`, `NAMESPACE=`, `PULL=` key/value lines plus a `### roster` block (top 15 active tasks by `last_updated`, one tab-separated line each). Internally handles: LDAP resolve (24h cached), namespace bootstrap, rate-limited `git pull` (5-min stamp), `.gitconfig.lock` cleanup, autosave-if-dirty.

Skip re-invocation within the same session — preamble.sh is idempotent but the tool turns aren't free.

### Tracker hydration (after preamble)

For each active task with open `## Next` items you intend to act on, call `TaskCreate`. **Emit every `TaskCreate` call as parallel tool calls in a single tool-use turn** — one assistant message with N concurrent `TaskCreate` blocks, not N sequential turns. Dedupe first: call `TaskList`, lowercase + strip each existing subject, skip kernel items that already match. Cap at ~10 tracker entries total (most-recently-updated tasks first).

If the roster gave you enough orientation, skip hydration. If you need the full kernel detail, Read `$WORKLOG_REPO/.cache/compact-kernels.md` (~95KB) on-demand — never automatically.

For per-task detail, use `"$WORKLOG_BIN/context.sh" <slug>` (its output ends in a `Tracker-ready snippet` block formatted for parallel `TaskCreate`).

### AGENTS.md / cheatsheet / lessons.md

- `$WORKLOG_REPO/AGENTS.md`: read only when the mode table says yes, OR when this quickref doesn't answer a specific question (frontmatter schema edge case, FSM corner, rare relation field). Per-clone — each clone has its own copy seeded from `$WORKLOG_BIN/../templates/AGENTS.md`.
- `$WORKLOG_BIN/../templates/docs/cheatsheet.md`: superseded by the Quickref section below for routine work. Open only for the long-tail (semantic search filter syntax, project subcommand flags, SQL helper details).
- `$WORKLOG_BIN/../templates/docs/lessons.md`: high-recurrence lessons live in Claude memory (`feedback_lessons.md`) — no read needed for non-review modes.

## Quickref — imperatives only (baked from cheatsheet)

### Slugs
- Grammar: `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. Linear ID known → `eng-<N>-<desc>`. Else bare `<desc>`. No `wip-`.
- Rename: `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>`. Cross-task rewrites: `"$WORKLOG_BIN/refactor.sh" <new> --rename=<old>`.

### Status FSM
- Linear: `draft → in-progress → in-review → shipping → archived`.
- Side: `blocked` — `next_action` MUST start with `Waiting on`.
- Flip via `"$WORKLOG_BIN/checkpoint.sh" <slug> --status=X`. Never edit frontmatter `status:` alongside a separate `Worklog-Status:` trailer.
- `--status=archived` is rejected by checkpoint — use `"$WORKLOG_BIN/archive.sh" <slug> --reason=<shipped|superseded|abandoned|merged|obsolete>`.

### Editing rules
- Edit only `$WORKLOG_REPO/people/$LDAP/`. Other namespaces read-only.
- Never `git rebase` / `git pull --rebase` / force-push during normal sync. Maintenance ops (`$WORKLOG_BIN/log-compact.sh`, `$WORKLOG_BIN/cache-purge.sh`) are the carve-out — see AGENTS.md.
- Prior-art grep before infra surfaces: `"$WORKLOG_BIN/related-search.sh" <keyword>`.

### Tooling shortlist
- Save: `"$WORKLOG_BIN/checkpoint.sh" <slug>` (single) · `"$WORKLOG_BIN/checkpoint-batch.sh" < json` (atomic multi).
- Archive: `"$WORKLOG_BIN/archive.sh" <slug> --reason=<…>`.
- Safety: `"$WORKLOG_BIN/autosave.sh"` (slugless snapshot). Hooks wired by `"$WORKLOG_BIN/install-hooks.sh" --write`.
- Standup: `"$WORKLOG_BIN/status.sh" [--since=… --project=… --slug=…]`.
- Per-task pack: `"$WORKLOG_BIN/context.sh" <slug> [--for=resume|review|compact]`.
- Slug lookup: `"$WORKLOG_BIN/slug.sh" <fragment>`.
- Search: `"$WORKLOG_BIN/search.sh" <pattern> [--active|--archive] [--kind= --status= --project= --linear= --pr= --repo= --ldap=]`; `--list` (slugs only), `--json`, `--semantic [--top=N]`.
- Graph viewer: `"$WORKLOG_BIN/worklog-manager" graph --repo "$WORKLOG_REPO" --format html --output /tmp/worklog-graph.html [--project=slug] [--match=text]`.
- Issue dispatch: `"$WORKLOG_BIN/worklog-manager" dispatch --config <instance.json> --issue <issue.json> --output /tmp/dispatch.json` writes local artifacts; `--execute` runs the planned sandbox argv only when instance config and `Worklog-Execute: sandbox` both approve it.
- Issue poll dry-run: `"$WORKLOG_BIN/worklog-manager" poll --config <instance.json> --issue-url https://github.com/<owner>/<repo>/issues/<n> --output /tmp/poll.json` fetches through `gh api`, updates local cursor/run artifacts, and posts no GitHub comments unless `--post-status` is passed.
- Multi-task project: `"$WORKLOG_BIN/project.sh" new|next|claim|release|reap|verify|list <slug>`.
- Lint: `"$WORKLOG_BIN/lint.sh" [--cross-task]`. Composite audit: `"$WORKLOG_BIN/audit.sh"`.
- SQL: `"$WORKLOG_BIN/sql.sh" new|run|list|show <slug> <name>`.
- New data repo: `"$WORKLOG_BIN/init-new-data-repo.sh" <path> [<ldap>]` (Phase 4 — not shipped yet).

### Frontmatter
- `kind` ∈ {bug, bugfix, cleanup, debug, design, impl, infra, investigation, ops, perf, plan, postmortem, program, proposal, review, runbook, spike, tooling}.
- Notion page IDs → `notion: <id>` (no dashes), NOT `external_refs:`. `init --full` matches against `notion:`.

### Body
- Cite cross-task refs in `related[]`, not just prose.
- Bare body slugs auto-wrap to `[[<slug>]]` via `"$WORKLOG_BIN/auto-slug-link.py"`. Frontmatter slugs stay bare.
- Round-trip safe: `grep -l '<slug>' people/` matches both forms.

### Commits
- `Worklog-Slug:` trailer MUST resolve to an existing task file.
- `Worklog-Status:` trailer MUST match frontmatter `status:` for that slug.
- Both enforced by `bin/git-hooks/commit-msg`. Hand-rolling status flips via trailer alone is rejected.

### Hooks
- Pre-commit blocks: lint errors on staged task files, scrubber regressions, ruff/shellcheck errors, secrets via `"$WORKLOG_BIN/pre-commit-scan.sh"`.
- Commit-msg blocks: typo `Worklog-Slug:`, trailer-vs-frontmatter drift.
- Post-commit advisory (TTL 1h): cross-task lint warnings, retro prompt on archive.
- Bypass any hook (one-shot, last-resort): `WORKLOG_NO_HOOK=1 git commit …`.

### Sessions
- Multi-session collision warning on `checkpoint.sh` if another session touched same slug <5min ago. Advisory; never blocks.
- Resume kernels live at `.cache/compact-kernels.{md,json}`. Preamble emits a top-15 roster from `.json`; only Read the `.md` (~95KB) on-demand for full detail.

## Slug & shared boundaries

- Only edit files under `people/$LDAP/`.
- Follow AGENTS.md checkpoint discipline after any mode completes.
- Prefer `"$WORKLOG_BIN/checkpoint.sh"` and `"$WORKLOG_BIN/autosave.sh"` over hand-rolling commits. New helper needed → new single-purpose script.

## Codex / Cursor / other agents

Non-Claude agents don't invoke this skill. They read `README.md` and `AGENTS.md` directly. Subcommand hints for them live in `README.md` § Helpers — keep that list in sync with the menu above when modes change.
