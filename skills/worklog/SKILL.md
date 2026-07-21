---
name: worklog
description: One skill for the shared `_worklog` repo. Twelve modes — `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `project`, `scrape-slack`, `review`. Invoke as `/worklog MODE [args]`. Bare `/worklog` or `/worklog help` prints the subcommand menu and stops. Unknown arg → show menu.
---

# worklog

Single entry point for the shared `_worklog` protocol. Canonical protocol lives in `_worklog/AGENTS.md`. This file is a thin router. Mode detail lives in `modes/<name>.md`; the compact protocol reference lives in `references/protocol.md`. Load both only when routed below.

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

## Mode → preamble requirement

| Mode    | Preamble | `references/protocol.md` | Reads AGENTS.md? | lessons.md? |
|---------|----------|--------------------------|------------------|-------------|
| init    | `--full` | no                       | yes              | quickref (limit=15) |
| sync    | `--full` | only when creating or hand-editing a task | only for an edge case the reference does not answer | no |
| status  | `--minimal` | no                    | no               | no |
| context | `--minimal` | no                    | no               | no |
| plan    | none     | no                       | no               | no |
| spawn   | none     | no                       | no               | no |
| export  | none     | no                       | no               | no |
| import  | none     | no                       | no               | no |
| lint    | none     | no                       | no               | no |
| project | `--minimal` (read-only subs); `--full` (mutating) | no | no | no |
| scrape-slack | none | no                      | no               | no |
| review  | `--full` | no                       | yes              | full |

## Paths — single source of truth

Scripts live in the dotfiles skill, NOT in the data repo:

```bash
WORKLOG_BIN="${WORKLOG_BIN:-$HOME/Documents/oss/dotfiles/skills/worklog/bin}"
WORKLOG_REPO="${WORKLOG_REPO:?per-clone .envrc must export this}"
```

Every example below uses `$WORKLOG_BIN/foo.sh` — these are the dotfiles-shipped scripts. The `WORKLOG_REPO` env var (set by each clone's `.envrc`) tells the scripts which data repo they're operating on; identity (LDAP) is resolved per-clone from `WORKLOG_LDAP` env, else git email, else `$USER`.

## Environment bootstrap contract

Run helpers from a shell that has the target clone's environment loaded. Prefer `direnv exec "$WORKLOG_REPO" ...` when the clone has `.envrc`; direct `source` is only safe for plain shell exports and may fail on direnv helpers such as `source_up`. Required shape:

- `WORKLOG_REPO` points at the live data repo (`.../_worklog`).
- `WORKLOG_BIN` points at this skill's `bin/` directory; if unset, use `$HOME/Documents/oss/dotfiles/skills/worklog/bin`.
- `WORKLOG_LDAP` is optional but authoritative when set; otherwise helpers fall back to git email, then `$USER`.
- `--help` paths must not require any of those variables to be set.

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

### AGENTS.md / protocol reference / lessons.md

- `$WORKLOG_REPO/AGENTS.md`: read only when the mode table says yes, OR when `references/protocol.md` does not answer a specific edge case. Per-clone — each clone has its own copy seeded from `$WORKLOG_BIN/../templates/AGENTS.md`.
- `references/protocol.md`: read only when the mode table says yes. It is the compact task-writing and helper reference formerly embedded here.
- `$WORKLOG_BIN/../templates/docs/cheatsheet.md`: open only for the long-tail (semantic search filter syntax, project subcommand flags, SQL helper details).
- `$WORKLOG_BIN/../templates/docs/lessons.md`: high-recurrence lessons live in Claude memory (`feedback_lessons.md`) — no read needed for non-review modes.

## Slug & shared boundaries

- Only edit files under `people/$LDAP/`.
- Follow AGENTS.md checkpoint discipline after any mode completes.
- Prefer `"$WORKLOG_BIN/checkpoint.sh"` and `"$WORKLOG_BIN/autosave.sh"` over hand-rolling commits. New helper needed → new single-purpose script.

## Skill maintenance opt-in

For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

Do not invoke it for normal `/worklog` runtime.

## Codex / Cursor / other agents

Codex agents may invoke this skill directly. Hydrate live progress with Codex `update_plan` wherever this protocol says Claude Code should use `TaskCreate`; `modes/init.md`, `modes/context.md`, and `modes/sync.md` carry the mode-specific tracker rules.

Cursor and other agents without this skill should read `README.md` and `AGENTS.md` directly. Subcommand hints for them live in `README.md` § Helpers — keep that list in sync with the menu above when modes change.
