# _worklog

## Quickstart (fresh machine)

```bash
gh repo clone ideogram-ai/_worklog ~/Documents/projects/_worklog
cd ~/Documents/projects/_worklog
WORKLOG_BIN="${WORKLOG_BIN:-$HOME/Documents/oss/dotfiles/skills/worklog/bin}"
"$WORKLOG_BIN/install-hooks.sh" --write
```

Then in a fresh Claude Code session: `/worklog init`.

---

Cross-machine, cross-agent work journal for Ideogram engineers. Git is the sync fabric so laptops, desktops, and LLM sessions (Claude Code, Codex, Cursor) share the same task state.

- **Protocol:** see [`AGENTS.md`](./AGENTS.md). Auto-loaded by Codex; read by Cursor; loaded by Claude Code via the kickoff prompt below.
- **Layout:** `people/<ldap>/active/<slug>.md` per in-flight task; `people/<ldap>/archive/<slug>.md` once terminal.
- **Branching:** none. Commit to `main` from every machine. Linear history during normal sync — `git pull --no-rebase`, never rebase. Maintenance ops (log compaction, cache purge) *do* rewrite history; they tag `pre-<op>-<ts>` and `"$WORKLOG_BIN/post-rewrite-prompt.sh"` emits the recovery prompt for other clones. See `AGENTS.md` § Editing rules.
- **Helpers:** shipped by the dotfiles skill, not this data repo's `bin/`: `"$WORKLOG_BIN/checkpoint.sh"` (per-task update), `"$WORKLOG_BIN/archive.sh"` (ship/supersede), `"$WORKLOG_BIN/autosave.sh"` (slugless snapshot), `"$WORKLOG_BIN/status.sh"` (standup summary), `"$WORKLOG_BIN/context.sh"` (per-task context pack), `"$WORKLOG_BIN/init-scan.sh"` (read-only exact-scan seeds for `/worklog init --full`), `"$WORKLOG_BIN/lint.sh"` (per-file format + `--cross-task` for stale-review / blocked-FSM / undeclared-body-ref drift), `"$WORKLOG_BIN/boundary-lint.sh"` (clone-boundary drift when `.worklog-boundary.json` exists).
- **Vault shape:** `_worklog/` opens as an Obsidian vault — folder of `.md` files with YAML frontmatter; no `.obsidian/` is checked in, so a fresh open creates a default workspace. The primary value is **Dataview queries over frontmatter** (consistent `slug` / `status` / `kind` / `last_updated` / `project` etc.). Caveat: relational edges (`parent_slug`, `related`, `supersedes`, `superseded_by`, `reopens`, project `tasks[].depends_on`) are stored as **bare slugs** because grep-as-index is load-bearing (see `AGENTS.md` "Slug as join key"). Obsidian's core graph won't traverse bare-slug frontmatter values — use `worklog-manager graph` for the protocol graph, or install Dataview (link-coercion via `dv.pages()`) / a plugin like *Frontmatter Links* for Obsidian-native views. Backlinks are sparse today since body text rarely uses `[[wikilinks]]` (the `auto-slug-link` idea in `archive/worklog-review-brainstorm.md` is the future path). Slug-grep + `git log --grep="Worklog-Slug: <slug>"` remains the authoritative join.

## Claude Code users

One skill, eleven modes — see `~/.claude/skills/worklog/SKILL.md`. Bare `/worklog` (or `/worklog help`) prints the subcommand menu.

First parse on a new machine/session:

- If `~/.claude/skills/worklog/SKILL.md` exists, use it. It is the
  first-class Claude entry point for this repo.
- If it does not exist yet, use the kickoff prompt below to work from the
  repo directly, then install or sync the Claude skill before relying on
  `/worklog`.

- `/worklog init` — first-time onboarding on a new machine (optionally `--full` to scan GitHub/Linear/Notion). For non-Claude agents, prefer `bin/init-scan.sh --format=json` as the deterministic seed pack before calling external tools.
- `/worklog sync [<slug>]` — contextual save: checkpoint, archive, backfill, or autosave — picks the right path from context.
- `/worklog status [--since=... --slug=... --project=... --format=...]` — read-only standup summary from `git log` + `Worklog-*` trailers.
- `/worklog context <slug> [--for=resume|review]` — single-shot context pack for one task.
- `/worklog plan <task>` — emit a structured CoT/ToT/Reflexion plan block for a new task (paste-ready into a task body).
- `/worklog spawn <task>` — emit a self-contained handoff prompt for a fresh session.
- `/worklog export` — emit the sanitized setup artifact for repo + local agent skills; agent settings stay advisory-only.
- `/worklog import <path>` — merge an export artifact into this machine with per-file judgment and advisory-only settings handling.
- `/worklog lint [--cross-task]` — validate task files (per-file format; `--cross-task` adds FSM/stale-review/undeclared-ref drift checks).
- `/worklog project <subcommand>` — multi-task project workflow (`new|next|claim|release|reap|verify|list`).
- `/worklog review` — periodic protocol review across structure, skills, commands, performance, and cross-session friction.

## Codex users

See [`docs/codex-setup.md`](./docs/codex-setup.md) for install + the manual session-end flow (Codex has no hooks equivalent; `"$WORKLOG_BIN/autosave.sh"` + `"$WORKLOG_BIN/compact-kernels.sh"` are run by hand before ending a conversation).


Codex does not have Claude's custom slash-command runtime, so `_worklog`
defines a **prompt-level first-class command** instead:

- `worklog help` — explain the available subcommands
- `worklog init [--full]` — onboarding / read-only init scan
- `worklog sync [<slug>]` — contextual save: checkpoint, archive,
  backfill, or autosave
- `worklog status [--since=... --slug=... --project=... --format=...]`
  — read-only standup/status summary
- `worklog context <slug> [--for=resume|review]` — single-task context
  pack
- `worklog plan <task>` — emit a structured CoT/ToT/Reflexion plan block
  for a new task
- `worklog spawn <task>` — emit a self-contained handoff prompt for a fresh
  session
- `worklog export` — emit the sanitized setup artifact
- `worklog import <path>` — analyze or merge a setup artifact into this
  machine
- `worklog lint [--cross-task]` — validate task files (per-file format;
  `--cross-task` adds drift checks)
- `worklog project <subcommand>` — multi-task project workflow
- `worklog review` — periodic protocol review; Codex uses `update_plan`
  instead of Claude `TaskCreate`

First parse on a new machine/session:

- If `~/.codex/skills/worklog/SKILL.md` exists, treat it as the
  Codex-native first-class interface for `worklog`.
- If it does not exist yet, read this repo's `AGENTS.md`, use the kickoff
  prompt below, and route `worklog ...` to the `$WORKLOG_BIN/*` helpers
  directly until the skill is installed.
- After installing or updating the Codex skill, restart Codex so it can be
  discovered by name.

When a user types one of the forms above in Codex, interpret it as an
explicit request to run the corresponding `_worklog` workflow, using the
helpers in `$WORKLOG_BIN` plus the protocol in `AGENTS.md`. Do not answer with a
generic explanation of what the command *would* do — actually perform the
workflow unless the user is clearly asking how it works.

Command mapping:

- `worklog init` → repo setup + LDAP resolution + `"$WORKLOG_BIN/init-scan.sh"`
- `worklog sync <slug>` → usually `"$WORKLOG_BIN/checkpoint.sh" <slug> ...` or
  `"$WORKLOG_BIN/archive.sh" <slug> ...`; if no slug is discoverable, `"$WORKLOG_BIN/autosave.sh"`
- `worklog status ...` → `"$WORKLOG_BIN/status.sh" ...`, then synthesize the result
  into prose per `AGENTS.md`
- `worklog context <slug> ...` → `"$WORKLOG_BIN/context.sh" <slug> ...`
- `worklog plan <task>` → render a fenced CoT/ToT/Reflexion plan block; do not execute it
- `worklog spawn <task>` → render a fenced handoff prompt; do not execute it
- `worklog project <subcommand>` → route to `"$WORKLOG_BIN/project.sh" <subcommand> ...`
- `worklog review` → create/update a review task and checkpoint iterations

For a fresh Codex session, start with the kickoff prompt below.

## Other agents (Codex kickoff, Cursor, …) — paste this prompt

```
Set up ideogram-ai/_worklog as a sibling of the current repo. If the clone is
missing, clone it into the parent of the current repo (or ~/Documents/projects /
~/projects / ~/code — else ask). Then:

  cd _worklog
  git config pull.rebase false && git config pull.ff true
  git pull --no-rebase --autostash
  read AGENTS.md and follow it

Resolve LDAP using the AGENTS.md order (gcloud account -> git email -> $USER)
and echo it. Treat these cold-start cases as normal:
- no local people/<ldap>/ directory yet
- no commits in _worklog authored by that LDAP yet

For read-only init --full:
- run `"$WORKLOG_BIN/init-scan.sh" --format=json`
- if it returns zero tasks, do not treat that as an error; it just means no
  worklog tasks exist yet for this LDAP
- in that case, widen outward and survey GitHub / Linear / Notion directly
  instead of relying on worklog history
- before proposing a task from a Linear/Notion hit, check merged/closed GitHub
  PRs for matching issue IDs or title keywords; shipped work is history, not a
  new active task
- show grouped candidate task files and wait for confirmation before writing

Helpers live in `$WORKLOG_BIN` — each script self-documents via `--help`:
  checkpoint.sh  archive.sh  autosave.sh  status.sh  context.sh  init-scan.sh  boundary-lint.sh
```
