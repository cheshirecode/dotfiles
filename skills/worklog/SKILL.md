---
name: worklog
description: One skill for the shared `_worklog` repo. Ten modes — `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `review`. Invoke as `/worklog <mode> [args]`. Bare `/worklog` or `/worklog help` prints the subcommand menu and stops. Unknown arg → show menu.
---

# worklog

Single entry point for the shared `_worklog` protocol. Canonical protocol lives in `_worklog/AGENTS.md` — do not duplicate it here.

This file is a **router**. Mode detail lives in `modes/<name>.md` and is loaded on-demand. Do NOT load mode files you aren't invoking.

## Routing — first thing, before anything else

Parse the first argument. If it's empty, `help`, `-h`, `--help`, or not in the mode table below, print the menu verbatim and **stop** — no preamble, no tool calls, no file reads.

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

Known modes: `init`, `sync`, `status`, `context`, `plan`, `spawn`, `export`, `import`, `lint`, `project`, `review`, `help`. Anything else → menu.

Once a known mode is parsed: run preamble (if required — see table), read `modes/<mode>.md`, follow it.

## Mode → preamble requirement

| Mode    | Needs preamble? | Reads AGENTS.md? | lessons.md? |
|---------|-----------------|------------------|-------------|
| init    | yes             | yes              | quickref (limit=15) |
| sync    | yes             | only if writing a new/existing task file | no |
| status  | yes (minimal — LDAP + projects-dir only; no pull) | no | no |
| context | yes (minimal)   | no               | no |
| plan    | no              | no               | no |
| spawn   | no              | no               | no |
| export  | no              | no               | no |
| import  | no              | no               | no |
| lint    | no              | no               | no |
| project | yes (minimal — LDAP only; no pull for read-only subcommands) | no | no |
| review  | yes             | yes              | full |

## Preamble — run only if the mode column above says yes

Skip any step you already completed earlier in the current conversation turn — don't re-resolve LDAP, re-pull, or re-read AGENTS.md within a single session.

0. **Resume kernels first.** Check `$PROJECTS_DIR/_worklog/.cache/compact-kernels.md` programmatically:
   ```bash
   f="$PROJECTS_DIR/_worklog/.cache/compact-kernels.md"
   [ -f "$f" ] && [ $(( $(date +%s) - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f") )) -lt 3600 ] && echo read
   ```
   If it echoes `read`, Read the file before anything else — it's the per-active-task resume summary auto-dumped by `PreCompact` / `SessionEnd` hooks. Orients you on all active tasks for the cost of one small file. If absent or stale (>1h), skip silently and fall through to per-task reads. The file itself also carries a `# Stale after: <ISO>` header as a secondary freshness cue.

   **Tracker hydration:** `bin/compact-kernels.sh` also emits `.cache/compact-kernels.json` — same data, machine-shaped: `[{slug, status, last_updated, last_sha, next_action, open_items}, ...]`. After reading the .md, walk the JSON and call `TaskCreate` once per `open_items` entry across active tasks (subject = item, description = `<slug>: <status>`). Cap at ~10 total tasks to keep the tracker focused; pick most-recently-updated slugs first.

   **Dedupe before TaskCreate.** Call `TaskList` first; collect existing tracker subjects (lowercased + stripped of leading/trailing whitespace). Skip any `open_items` text that already matches. The kernel JSON is read-only; the tracker is one-way (no upsert API); skip-already-present is the only protection against duplicates on preamble re-entry within the same session (`/clear`, mid-conversation tooling re-entry, repeated `/worklog` invocations).

   This mechanical hydration closes the "Claude forgot to hydrate" loophole from `worklog-review-2026-04` Tier-1 #5; the dedupe step closes the "Claude hydrated twice" follow-on (worklog-task-create-dedupe).
1. **Resolve LDAP.** `bin/_lib.sh::resolve_ldap` (`WORKLOG_LDAP → repo git email → cheshirecode`). Echo it.
2. **Resolve `$PROJECTS_DIR`.** `dirname "$(git rev-parse --show-toplevel 2>/dev/null)"`; else first existing of `~/Documents/projects` `~/projects` `~/code` `~/src` `~/dev` `~/repos`; else ask.
3. **Sync worklog repo** (skip for status/context — they're read-only and stale-tolerant):
   ```bash
   [ -d "$PROJECTS_DIR/_worklog" ] || gh repo clone cheshirecode/_worklog "$PROJECTS_DIR/_worklog"
   cd "$PROJECTS_DIR/_worklog"
   git config pull.rebase false; git config pull.ff true
   # Pre-pull dirty check (advisory): autostash silently moves edits and can
   # pop with conflicts that go unnoticed. If dirty, run autosave first.
   . bin/_lib.sh
   if ! detect_dirty_worklog; then
     bin/autosave.sh
   fi
   git pull --no-rebase --autostash
   ```
   **Never** `git rebase` or `git pull --rebase` during normal sync — checkpoints are the audit trail. Maintenance ops (`bin/log-compact.sh`, `bin/cache-purge.sh`) rewrite history deliberately and emit a recovery prompt via `bin/post-rewrite-prompt.sh`. See `AGENTS.md` § Editing rules.
4. **Ensure namespace.** If `people/$LDAP/` missing, create `{active,archive}/` with `.gitkeep` in `archive/`, commit + push.
5. **Read `docs/cheatsheet.md` first.** Imperative-only quick-card derived from AGENTS.md (~50 lines). Covers slug grammar, FSM, editing rules, tooling shortlist, hooks, body conventions. Consult AGENTS.md (next step) only when the cheatsheet doesn't answer a specific question.
6. **Read AGENTS.md** only when the table above says yes (`init` and `review` always; others if cheatsheet didn't suffice). Authoritative for task-file format, status FSM, checkpoint discipline, editing rules — the *why* behind every cheatsheet imperative.
7. **Read `docs/lessons.md` per the table above.** High-recurrence lessons are distilled in Claude memory (`feedback_lessons.md`) and load without a file read — no need to re-derive them from the ledger. For `review`: read the full file. For `init --full`: read quickref only (`limit=15`, covers the `## Quickref` header). All other modes: skip — the memory-resident lessons cover the dominant failure modes. Skip on subsequent preambles in the same conversation turn.

## Slug & shared boundaries (cross-mode, always apply)

Slug grammar: `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. Linear ID known → `eng-<N>-<desc>`. Not yet → bare `<desc>`. No `wip-` prefix. Rename via `bin/checkpoint.sh <new> --rename=<old>`.

- Only edit files under `people/$LDAP/`.
- Follow AGENTS.md checkpoint discipline after any mode completes.
- Never `git rebase`, `git pull --rebase`, or force-push during normal sync. Maintenance ops are the carve-out — see AGENTS.md.
- Prefer `bin/checkpoint.sh` and `bin/autosave.sh` over hand-rolling the commit dance. New helper needed → new single-purpose script, don't widen an existing one.

## Codex / Cursor / other agents

Non-Claude agents don't invoke this skill. They read `README.md` and `AGENTS.md` directly. Subcommand hints for them live in `README.md` under "Helpers" — keep that list in sync with the menu above when modes change.
