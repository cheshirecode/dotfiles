---
name: worklog
description: Manage the shared `_worklog` journal across machines and sessions. Twelve modes — `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `project`, `scrape-slack`, `review`. Invoke as `/worklog MODE [args]`. Bare `/worklog`, `/worklog help`, or unknown args print the subcommand menu and stop.
---

# worklog

Single entry point for the shared `_worklog` protocol. Canonical protocol lives in `_worklog/AGENTS.md`. This file is a thin router. Mode detail lives in `modes/<name>.md`; the compact protocol reference lives in `references/protocol.md`. Load both only when routed below.

## When to use

- Managing the shared `_worklog` journal across machines and sessions
- Invoking any worklog mode: `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `project`, `scrape-slack`, `review`

Skip if: no durable task tracking or cross-session context is needed.

## Skill structure

```
skills/worklog/
├── SKILL.md              # this file (router)
├── modes/                # per-mode execution guides
│   ├── registry.md       # public mode list (consumed by codex-surface-check.sh)
│   ├── init.md, sync.md, status.md, context.md, plan.md, spawn.md,
│   │   export.md, import.md, lint.md, project.md, scrape-slack.md, review.md
├── references/
│   └── protocol.md       # compact task-writing and helper reference
├── bin/                  # helper scripts (WORKLOG_BIN)
├── lib/                  # shared shell libraries
├── templates/            # AGENTS.md template, docs/, cheatsheets
└── tests/                # e2e harness
```

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
  scrape-slack [flags]     preview Slack-derived task context enrichments
  review                   periodic protocol review (structure / skills / commands / perf)
  help                     this menu

flags detail: see modes/<name>.md
```

Once a known mode is parsed: run preamble (per table), read `modes/<mode>.md`, follow it. Read `references/protocol.md` only when the table says so or the selected mode explicitly directs it. Do not preload other mode or reference files.

**Unknown mode:** if the first argument is not `help`, `-h`, `--help`, or a known mode name, print the menu verbatim and stop. Do not guess or suggest corrections.

## Mode → preamble requirement

| Mode    | Preamble | `references/protocol.md` | Reads AGENTS.md? | lessons.md? |
|---------|----------|--------------------------|------------------|-------------|
| init    | `--minimal` (default and `--light`); `--full` (explicit `--full`) | no | yes | quickref (limit=15) |
| sync    | `--full` | only when creating or hand-editing a task | only for an edge case the reference does not answer | no |
| status  | `--minimal` | no                    | no               | no |
| context | `--minimal` | no                    | no               | no |
| plan    | none     | no                       | no               | no |
| spawn   | none     | no                       | no               | no |
| export  | none     | no                       | no               | no |
| import  | none     | no                       | no               | no |
| lint    | none     | no                       | no               | no |
| project | `--minimal` (read-only subs: `list`, `verify`, `next`); `--full` (mutating: `new`, `claim`, `release`, `reap`) | no | no | no |
| scrape-slack | none | no                      | no               | no |
| review  | `--full` | no                       | yes              | full |

## Paths — single source of truth

Scripts live in the dotfiles skill, NOT in the data repo:

```bash
WORKLOG_BIN="${WORKLOG_BIN:-$HOME/Documents/oss/dotfiles/skills/worklog/bin}"
WORKLOG_REPO="${WORKLOG_REPO:?per-clone .envrc must export this}"
```

Every example below uses `$WORKLOG_BIN/foo.sh` — these are the dotfiles-shipped scripts. The `WORKLOG_REPO` env var (set by each clone's `.envrc`) tells the scripts which data repo they're operating on; identity (LDAP) is resolved per-clone from `WORKLOG_LDAP` env, else git email, else `$USER`.

**Key distinction:** `WORKLOG_BIN` is the code (this skill, version-controlled in dotfiles); `WORKLOG_REPO` is the data (the `_worklog` clone, per-machine). They are separate repos with separate lifecycles.

## Environment bootstrap contract

Run helpers from a shell that has the target clone's environment loaded. Prefer `direnv exec "$WORKLOG_REPO" ...` when the clone has `.envrc`; direct `source` is only safe for plain shell exports and may fail on direnv helpers such as `source_up`. Required shape:

- `WORKLOG_REPO` points at the live data repo (`.../_worklog`). **Required for all modes except `help`.** If unset and the mode is not `help`, error with: `WORKLOG_REPO not set — run from a worklog clone or set it explicitly.`
- `WORKLOG_BIN` points at this skill's `bin/` directory; if unset, use `$HOME/Documents/oss/dotfiles/skills/worklog/bin`.
- `WORKLOG_LDAP` is optional but authoritative when set; otherwise helpers fall back to git email, then `$USER`.
- `--help` paths must not require any of those variables to be set.

**Error handling:** if a helper script exits non-zero, report the error verbatim and stop. Do not retry or work around script failures — the user needs to see the actual failure mode. Exception: `lint.sh` warnings during `sync` are advisory (see `modes/sync.md`).

## Preamble — single call

```bash
cd "$WORKLOG_REPO" && "$WORKLOG_BIN/preamble.sh" [--minimal|--full]
```

Emits `LDAP=`, `PROJECTS_DIR=`, `NAMESPACE=`, `PULL=` key/value lines plus a `### roster` block (top 15 active tasks by `last_updated`, one tab-separated line each). Both paths resolve LDAP and inspect the namespace/roster. Full mode additionally handles the rate-limited pull and dirty-tree autosave.

Skip re-invocation within the same session — preamble.sh is idempotent but the tool turns aren't free.

### Tracker hydration (after preamble)

After the preamble, if the user has selected or will act on a specific task, hydrate the in-session tracker for that task's unchecked `## Next` items. **Emit every `TaskCreate` call as parallel tool calls in a single tool-use turn** — one assistant message with N concurrent `TaskCreate` blocks, not N sequential turns. Dedupe first: call `TaskList`, lowercase + strip each existing subject, skip kernel items that already match. Cap at ~10 tracker entries total (most-recently-updated tasks first).

If the roster gave you enough orientation, skip hydration. If you need the full kernel detail, Read `$WORKLOG_REPO/.cache/compact-kernels.md` (~95KB) on-demand — never automatically.

For per-task detail, use `"$WORKLOG_BIN/context.sh" <slug>` (its output ends in a `Tracker-ready snippet` block formatted for parallel `TaskCreate`).

### AGENTS.md / protocol reference / lessons.md

- `$WORKLOG_REPO/AGENTS.md`: read only when the mode table says yes, OR when `references/protocol.md` does not answer a specific edge case. Per-clone — each clone has its own copy seeded from `$WORKLOG_BIN/../templates/AGENTS.md`.
- `references/protocol.md`: read only when the mode table says yes. It is the compact task-writing and helper reference formerly embedded here.
- `$WORKLOG_BIN/../templates/docs/cheatsheet.md`: open only for the long-tail (semantic search filter syntax, project subcommand flags, SQL helper details).
- `$WORKLOG_BIN/../templates/docs/lessons.md`: high-recurrence lessons live in Claude memory (`feedback_lessons.md`) — no read needed for non-review modes.

## Slug & shared boundaries

- Only edit files under `people/$LDAP/`. Other namespaces are read-only.
- Follow AGENTS.md checkpoint discipline after any mode completes.
- Prefer `"$WORKLOG_BIN/checkpoint.sh"` and `"$WORKLOG_BIN/autosave.sh"` over hand-rolling commits. New helper needed → new single-purpose script.
- **Never** force-push, rebase, or rewrite history in the worklog repo during normal operations. Maintenance ops (`log-compact.sh`, `cache-purge.sh`) are the carve-out — see AGENTS.md.

## Skill maintenance opt-in

For brittle outputs (mode files with complex conditional logic, multi-step workflows, or format-sensitive templates), invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

Do not invoke it for normal `/worklog` runtime.

## Codex / Cursor / other agents

Codex agents may invoke this skill directly. Hydrate live progress with Codex `update_plan` wherever this protocol says Claude Code should use `TaskCreate`; `modes/init.md`, `modes/context.md`, and `modes/sync.md` carry the mode-specific tracker rules.

Cursor and other agents without this skill should read `README.md` and `AGENTS.md` directly. Subcommand hints for them live in `README.md` § Helpers — keep that list in sync with the menu above when modes change.
