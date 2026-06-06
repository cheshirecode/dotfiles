# AGENTS.md — _worklog protocol

Scope: this file governs any session (human or agent) editing `_worklog`. Auto-loaded by Codex and agents that honor `AGENTS.md`; Claude Code loads it via the kickoff prompt in `README.md`.

Deep material and edge cases live in [docs/protocol.md](./docs/protocol.md) — includes task-file hygiene (signal vs. transient noise), review-loop conventions, FSM, kinds. Script composition playbook: [docs/helpers.md](./docs/helpers.md). Format rationale (why markdown + git, not embeddings): [docs/rag-format.md](./docs/rag-format.md). This file is the essentials.

## What this repo is

A shared journal of in-flight engineering work, synced via git across machines and LLM sessions. Not a ticket tracker (Linear owns that). Not a design doc (Notion owns that). This tracks **what is happening right now** so a fresh session on any machine can pick up without context hunting.

## Slug as join key — grep is the index

The slug is the content-addressable ID that binds every surface together. No bridge table, no mapping file, no secondary index — just literal-string grep across four surfaces:

| Surface                   | Where the slug appears                | Lookup primitive                                 |
| ------------------------- | ------------------------------------- | ------------------------------------------------ |
| Task file                 | `people/*/active/<slug>.md`           | `ls people/*/active/<slug>.md`                   |
| Worklog commit subject    | `<slug>: <event>`                     | `git log --grep="^<slug>:"`                      |
| Worklog commit trailer    | `Worklog-Slug: <slug>`                | `git log --grep="Worklog-Slug: <slug>"`          |
| Source-repo PR body       | `Worklog-Slug: <slug>` trailer        | `gh search prs "Worklog-Slug: <slug>" in:body`   |
| Source-repo branch        | `<ldap>/<slug>`                       | `gh pr list --head "*/<slug>"`                   |

**Forward (PR → task):** trailer or branch-tail → glob `people/*/active/<slug>.md`. LDAP falls out of the matched path. This is what the event-driven checkpoint workflow does.

**Reverse (task → PRs):** `git log --grep="Worklog-Slug: <slug>"` in `_worklog` enumerates every `Worklog-PR:` trailer ever attached to that slug. `bin/status.sh --slug=<slug>` already parses this.

**Authority rule:** trailers in git log are the source of truth for PR linkage. `pr:` frontmatter is an **optional cache** for human skim — never the index. `bin/checkpoint.sh --pr=N` writes both in sync, so drift shouldn't happen; if it does, trailers win.

Uniqueness invariant: slugs are globally unique across `people/*/`. That's what makes both the glob and the grep work without disambiguation. Enforced by convention — `bin/lint.sh` validates per-file format (see [docs/protocol.md § Lint rules](./docs/protocol.md#lint-rules)) but does not cross-check uniqueness. Collisions surface at write time: `ls people/*/active/<slug>.md` returning >1 match during checkpoint is the signal.

**SHAs are not navigation primitives.** History rewrites (Tier-2 squash, see `worklog-log-compaction-squash`) are an accepted maintenance event; SHAs cited in messages, PR descriptions, or task bodies dangle after a rewrite. Reference past work by `<slug> + commit subject prefix`, not by SHA.

## Slug grammar

```
^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$
```

- Bare descriptor (e.g. `pillbutton-style-merge`) is a first-class slug. No `wip-` placeholder.
- Optional `eng-<N>-` prefix (e.g. `eng-1515-stack`) when a Linear ID is already known at create time and you want grep to join against Linear.
- Descriptor: lowercase kebab, 1–4 tokens, ≤30 chars total.
- **Retroactive rename is optional, not mandatory.** If a Linear ID later becomes load-bearing for cross-referencing, `bin/checkpoint.sh <new-slug> --rename=<old-slug>` emits a `Worklog-Previous-Slug` trailer. Otherwise the bare slug stays — a Linear-less task is not provisional. Rename only while `status != archived`.

## Task file format

```
---
slug: <slug>
status: draft | in-progress | in-review | blocked | shipping | archived
kind: design | review | spike | impl | ops | debug | program | postmortem | runbook | proposal | bugfix | investigation | plan | infra   # extended; lint also grandfathers legacy bug | perf | tooling
repos: [<name>, ...]   # e.g. [ui, website]; [] for doc-only work
linear:                # optional; add ENG-<N> if/when one exists. Omit the key entirely when not applicable.
project:               # see "Resolving project:" below
last_updated: YYYY-MM-DD
next_action: "<one sentence — what unblocks progress>"
---

## Context
<what + why; link PRs, Linear IDs, Notion pages, file paths>

## Invariants
<facts that must not drift; shipped decisions>

## Next
<1–3 concrete bullets>
```

Optional sections as needed: `## Notes from <session>`, `## Open questions`, `## Risks`.

Optional frontmatter keys (`notion`, `pr`, `pr_repos`, `graphite_stack`, `reopens`, `external_refs`, plus relation keys below) — see [docs/protocol.md](./docs/protocol.md#optional-pipeline-indexed-frontmatter-keys).

`pr:` is a **cache** of the latest PR numbers for human skim. The authority is `Worklog-PR:` trailers in git log (keyed by `Worklog-Slug:`). `bin/checkpoint.sh --pr=N` writes both; the event-driven bot writes trailers without touching frontmatter. If they disagree, trailers win. Omitting `pr:` is fine — reverse-lookup by grep still works.

### Task relations

Four optional frontmatter keys express links between tasks. All single-direction — never write both sides.

- **`parent_slug: <slug>`** — points to the umbrella/program task (typically `kind: program`). Program stewards derive their children list with `bin/children.sh <self-slug>` (or `grep parent_slug: <self-slug> people/*/active/*.md people/*/archive/*.md` for a dependency-free fallback). Never add a `children:` key on the parent — the reverse index is always computed.
- **`related: [{slug, note}]`** — peer links that aren't parent/child. `note` is a one-line *why this relates* (purpose of the link), not a description of where the slug appears in the body. Required (otherwise the link rots). Lint auto-injects a `(auto-added; refine note)` placeholder when a body-mention is undeclared; refine it before archive — the lint warns if the placeholder survives. Good: `note: "carve-out regex lives there; keep invariants aligned"`. Bad: `note: "mentioned in Context section"` (rephrases the body, not the relation). Same shape as `external_refs:`.
- **`supersedes: <slug>`** — this task replaces an older approach that was abandoned mid-flight. Write it on the new task. On archiving the old one, add `superseded_by: <new-slug>` to its frontmatter and the one-line archive reason referencing the new slug.
- **`reopens: <slug>`** — post-archive regression or follow-on (existing key; see FSM).

Rules:

1. Always use the bare slug (no `.md`, no path). Grep joins on literal slugs.
2. A relation must resolve to a real file at write time (active or archive). Stale relations are drift — fix them in the next checkpoint.
3. Never two-way: if you add `parent_slug:` to a child, do not also list it under the parent's body or frontmatter. The reverse query is the source of truth.
4. Prefer `parent_slug:` over prose "`Follow-on from <parent>`" when the relation is durable (program → phase). Prose `Follow-on from …` still applies for proposal tasks where the parent is just conversational context.

Example:

```yaml
parent_slug: landing-page-rebuild
related:
  - slug: eng-1515-stack
    note: carve-out regex lives there; keep invariants aligned
supersedes: old-approach-slug
```

### Kinds are additive (Liskov)

`kind:` is a grep-friendly tag for task class — a hint, not a schema gate. A task's `kind:` may add optional frontmatter keys and body sections, but must never remove, rename, or override the required fields or the `## Context` / `## Next` sections. Any script or agent reading a task file must work uniformly across kinds. Detailed per-kind conventions: [docs/protocol.md](./docs/protocol.md#kinds--detailed-conventions).

### Resolving `project:`

The `project:` slug groups related tasks. Linear is one valid source among several — use whichever fits the task.

0. **First: enumerate existing values** with `bin/related-search.sh --projects` (or `awk '/^project:/{print $2}' people/*/active/*.md | sort -u`). Reuse a slug if your task fits an existing program. Only invent a new slug for genuinely new work. Avoid creating closely-named-but-distinct values — `marketing-site-2026` / `new-marketing-page-serving` / `marketing-intake` is the kind of sprawl this catches.
1. If `linear:` is set → fetch the issue, take the `project.url` slug verbatim so it joins against Linear without transformation.
2. If body has `ENG-\d+` refs and a dominant project emerges (>50% of referenced issues share a project) → propose that slug.
3. Otherwise → deduce a short, descriptive slug (kebab-case, 1–3 tokens) from task context. Ask the human to confirm before writing.
4. Explicitly projectless work → `project: none`.

When Linear has a matching project slug, prefer the verbatim match so cross-references work; when it doesn't, a deduced slug is a first-class choice, not a fallback.

## Status lifecycle

Six states, one terminal. Full FSM diagram + transition rules: [docs/protocol.md](./docs/protocol.md#status-lifecycle--full-fsm).

- **draft** — frontmatter exists; scope still shifting. Includes `kind: proposal`.
- **in-progress** — actively coding or designing. The 95% state.
- **in-review** — PR out for review. Reviewer feedback → back to `in-progress`.
- **blocked** — external dependency. `next_action` must read `Waiting on <concrete thing>`.
- **shipping** — PR merged, deploy pending. Archive only after deploy verified.
- **archived** — **terminal**. Lives in `people/<ldap>/archive/`. On archive, prepend to `## Context`: `Archived YYYY-MM-DD: <shipped | declined | abandoned>: <one-line reason>.`

**When in doubt, prefer fewer transitions.** Status is coarse triage; PR-phase nuance belongs in `next_action` prose. For post-ship regressions, open a new task with `reopens: <old-slug>`.

Proposal tasks (`kind: proposal` + `status: draft`) have their own 3-exit lifecycle — see [docs/protocol.md](./docs/protocol.md#proposal-tasks-unrealized-follow-ons).

## Editing rules

0. **Prior-art grep before editing infrastructure surfaces.** Before changing config that other tasks may have already settled — `gsutil` upload commands, nginx config, `proxy_pass` rules, terraform cache rules, image/video pipeline scripts, any `Cache-Control` decision — run `bin/related-search.sh <surface-keyword>` over active + recent-archive task bodies and skim the hits. Design tasks specify these decisions in prose; a code edit that flips them silently is the same class of error as inventing a conflicting decision in a new task (worklog-prior-art-check § Problem miss #4). The grep takes 5 seconds; reverting a wrong flip after PR review costs minutes-to-days. Companion to the [new]-task grep step in sync mode.
1. **Only edit files under your own `people/<ldap>/`.** To contribute to a peer's task, append a `## Notes from <your-ldap>` block at the bottom of their file and let the owner merge.
2. **Do not rename peers' files.** Open a new one in your own namespace if scope diverges.
3. **Frontmatter is required.** A task without frontmatter is not discoverable via grep.
4. **No secrets.** No API keys, tokens, private URLs beyond what Linear/GitHub already expose internally.
5. **Commit terse, push often.** Every meaningful state change is a commit. Noise is fine; staleness is not.
6. **No sibling directories under `people/<ldap>/`.** Only task `.md` files and (optionally) `.gitkeep`. Binary fixtures, JSON captures, scripts — live in the product repo the task's PR(s) touch.
7. **Never `git rebase` / `git pull --rebase` / force-push during normal sync.** Linear history is the audit trail. Carve-out: explicit maintenance ops *do* rewrite history — `bin/log-compact.sh` (compact same-slug checkpoint bursts), `bin/cache-purge.sh` (remove historical `.cache/` paths), or other deliberate cleanup. These tag `pre-<op>-<ts>` for recovery and assume single-committer windows. After any such op, run `bin/post-rewrite-prompt.sh` and paste its output to other live sessions so they reset cleanly. If `git pull` reports non-fast-forward and you didn't rewrite locally: `git stash push -u -m pre-recovery && git reset --hard origin/main && git stash pop`, then re-apply any wiped commits via reflog or by redoing the edits + checkpoint.

## Commit message convention

Goal: `git log` alone answers who touched which task when and whether state flipped.

### Subject

```
<slug>: <what changed>
```

- 80-char budget. Specific over generic.
- Meta commits without a single task: `protocol: ...`, `bin: ...`, `docs: ...`.

### Trailers (emit only when applicable; `bin/*` handle this automatically)

| Trailer                  | When to emit                                                                                   |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `Worklog-Status:`        | Only when `status:` frontmatter flips. Value is the **new** status.                            |
| `Worklog-Kind:`          | On `create` commits.                                                                           |
| `Worklog-Linear:`        | On `create` commits **only when a Linear ID exists**. Omit the trailer entirely otherwise — absence is the signal. |
| `Worklog-Project:`       | On `create` / status-flip / archive commits. Value is the `project:` frontmatter slug.         |
| `Worklog-PR:`            | Authority for task↔PR linkage. `bin/checkpoint.sh --pr=N` emits it; also auto-emitted from frontmatter `pr:` cache (comma-separated if multiple). |
| `Worklog-Previous-Slug:` | On rename commits. Value is the old slug.                                                      |

Prefixed (`Worklog-`) to avoid collision with git-standard trailers. LDAP is not a trailer — derivable from `git log --author` and the `people/<ldap>/` path.

Body convention: checkpoint commits include the current `next_action` as a one-line body prefixed `next: ` so `git log --format=%b` gives a readable "what's next per slug" view. Examples, noise filter, daily-summary recipe: [docs/protocol.md](./docs/protocol.md#commit-trailers--examples-and-body).

## Repo layout

```
_worklog/
├── README.md                        # 1-page intro + kickoff prompt
├── AGENTS.md                        # this file (essentials)
├── docs/
│   ├── protocol.md                  # deep material, edge cases
│   └── helpers.md                   # bin/* composition playbook
├── bin/                             # one-job scripts (checkpoint, archive, autosave, status, context)
└── people/<ldap>/{active,archive}/<slug>.md
```

## Resolving `<ldap>`

Auto-detect from the Google identity on the current machine — never hardcode. In order:

```bash
LDAP=$(gcloud config get-value account 2>/dev/null | sed 's/@.*//')
[ -z "$LDAP" ] && LDAP=$(git config --global user.email | sed 's/@.*//')
[ -z "$LDAP" ] && LDAP=$USER
```

Echo the resolved value so the human can confirm before the first write. If ambiguous (e.g., `gcloud` account is a non-Ideogram identity), ask.

## Resolving `$PROJECTS_DIR`

The worklog repo lives next to the user's other projects. Resolve in order:

1. `dirname "$(git rev-parse --show-toplevel 2>/dev/null)"` — parent of the current repo checkout (typical case).
2. First existing path from `~/Documents/projects`, `~/projects`, `~/code`, `~/src`, `~/dev`, `~/repos`.
3. Ask the user.

Codex and other agents without the Claude skill should use the same fallback list so machine-to-machine behavior stays consistent.

## User context

- **Primary user:** Fred Tran (LDAP: `<ldap>`). Others welcome to add `people/<their-ldap>/`.
- **Primary code repo:** `ui` (Python backend `api/` + React SPA `frontend/react/`); siblings `website`, `Landing-Page`, `devops-permissions`.
- **Conventions:** always read the target repo's root `AGENTS.md` before editing code. Graphite: `gt restack` + `gt submit --stack --no-edit`. Never plain `git push` on stack branches. Never edit generated code.
- **Worktree discipline:** always start new work in a git worktree — `git worktree add ../<repo>-<slug> -b <branch>`. The primary checkout is shared surface; keep it on `main`.

## First Parse Bootstrap

On the first parse of this repo in a fresh agent install, prefer the
agent-native `worklog` skill if it is already installed:

- **Claude Code:** `~/.claude/skills/worklog/SKILL.md`
- **Codex:** `~/.codex/skills/worklog/SKILL.md`

If the local skill is present, treat it as the first-class command surface
for that agent and keep its behavior aligned with this repo's `README.md`
and `AGENTS.md`.

If the local skill is missing:

1. Continue from the repo directly — do not block on missing skill install.
2. Read this file and use `_worklog/bin/*` as the workflow interface.
3. Treat `worklog ...` as a prompt-level command request anyway.
4. Once the skill is installed, prefer it on future sessions.

This keeps first-time parsing cold-start safe while still making the skill
the durable first-class interface once available.

## In-session progress visibility

The worklog is the **cross-session** journal. Agents **MUST** also show **in-session** progress so the human can follow along without re-reading the transcript. Open a task list up front for any multi-step work (≥3 steps, or any task with verification gates / deploy / review) and update each step as it moves `pending → in_progress → completed`. Mark each done immediately, not in a batch at the end.

**Self-check on every session resume + on starting any new multi-step task:** read the active task's `## Next` checkboxes; for each unchecked `- [ ]` item, add a tracker entry NOW (don't wait for the system reminder, don't wait for the user to ask). The `bin/context.sh <slug>` output's "Tracker-ready snippet" section formats each item ready to paste/exec — use it.

The protocol exists because agents drift. Documented evidence: 2026-04-27 review session ran ~30 multi-step commits with zero `TaskCreate` invocations despite the system reminder firing repeatedly (`docs/lessons.md` 2026-04 entry; `worklog-review-2026-04` Tier-1 #5).

Skip only for trivially small single-step asks (one edit, one command). Default to on; don't wait for the human to ask.

Per-agent mechanism:

- **Claude Code** — use the `TaskCreate` / `TaskUpdate` / `TaskList` tools. They render a live checklist in the UI.
- **OpenAI Codex CLI** — use the built-in `update_plan` tool (the "plan" / default TODO tool). The TUI renders the plan with step status. Emit an initial plan, then update step status as you work.
- **Cursor** — prefer the Agents Window canvas todo card (Cursor 3.x) when available; otherwise use Plan Mode for an upfront plan. If neither is wired up in the current session, maintain a plain `TODO:` block in the chat and tick items as you go.

Trivial single-step work is exempt for every agent.

For Codex specifically, treat `update_plan` as a **mirror**, not a second
source of truth. This Codex-only rule does **not** replace Claude Code's
existing `TaskList` UI or its `PreCompact` hook path.

- On task resume or the first `worklog ...` command in a session, read the
  task file's `## Next` checkboxes and recreate the current `update_plan`
  entries from each unchecked item.
- While working, keep `update_plan` current for in-session visibility.
- When the durable plan changes (checkbox completed, new blocker, reordered
  next step), update the task file and checkpoint it; do not leave the new
  state only in `update_plan`.
- There is no automatic hook from `_worklog` into Codex's tracker today.
  The sync contract is deliberate agent behavior: task file → `update_plan`
  on resume, then `update_plan` → task file on meaningful progress.

### Ephemerality + rehydration

In-session tracker state (`TaskList`, `update_plan`, canvas) does **not** survive `/compact` or a new session — it lives in agent memory only. The durable record is inline checkboxes in the task file's `## Next` body section. On resume: read the checkboxes first and recreate tracker entries for each unchecked item. `next_action:` frontmatter is always a single quoted sentence — it's a pointer to the body, not the decomposition itself.

### Surviving compaction

Compact proactively, not reactively — around 60% context, not when the warning fires. By the warning, the model is already summarizing a degraded view. Before `/compact`:

1. Run `/worklog sync` (or `bin/checkpoint.sh <slug>`) so the file holds current state, not the conversation.
2. Pass the worklog-aware instruction: `/compact $(cat docs/compact-instruction.md)` — it tells the model to anchor on slug + `next_action:` + last pushed SHA + mid-debug state, and to drop tool transcripts.

After `/compact` (or any session resume): **first check `_worklog/.cache/compact-kernels.md`** with a mtime gate:
```bash
[ -f .cache/compact-kernels.md ] && \
  [ $(( $(date +%s) - $(stat -f %m .cache/compact-kernels.md 2>/dev/null || stat -c %Y .cache/compact-kernels.md) )) -lt 3600 ]
```
If the gate passes, read it once for all-active-tasks orientation (~7 lines per task). The file also carries a `# Stale after: <ISO>` header as a secondary cue. If stale or absent, skip and fall through to per-task reads. Then **re-read `people/<ldap>/active/<slug>.md` before your first action**, and state the slug + `next_action:` back to the user as a verification check. If the compact summary and the file disagree, the file wins.

Claude Code only: wire `bin/autosave.sh` + `bin/compact-kernels.sh` as `PreCompact` and `SessionEnd` hooks so uncommitted task edits land in git before the summary bakes in, AND a resume kernel per active task is dumped to `.cache/compact-kernels.md` for the next session. `bin/install-hooks.sh --write` (idempotent). Codex CLI / Cursor have no hook equivalent; they rely on layer 3 (re-read the file on resume — and may manually run `bin/compact-kernels.sh` before ending a session). Full detail: [docs/protocol.md § Surviving compaction](./docs/protocol.md#surviving-compaction).

### Work breakdown with sequential-thinking

When decomposing a complex next step into substeps, prefer the `sequential-thinking` MCP (`mcp__sequential-thinking__sequentialthinking`) if available — it surfaces parallel gates and dependency edges that inline reasoning misses. Use when `## Next` has ≥4 implicit substeps or ambiguous ordering; skip for obvious linear work. The final thought list maps directly to `- [ ]` checkboxes under `## Next`.

### Hygiene

- Delete preview-only or exploratory tracker entries once the plan is written to disk.
- Before `/compact` or session end, every `in_progress` is either completed, flipped back to `pending` with a blocker note, or deleted.

## Checkpoint discipline

Every agent must checkpoint — **do not wait for the user to ask** — on:

1. **Verifiable progress** (PR opened, review arrived, blocker found, status flipped, `next_action` now wrong).
2. **Context pressure** (approaching compaction / long tool output / model summarization).
3. **End of turn with uncommitted task edits.**
4. **User signals** ("checkpoint", "wrap up", "save state", "switching machines").
5. **Scope change** — checkpoint the old task before pivoting.

Use `bin/checkpoint.sh <slug> [--status=X --next="..." --pr=N]` — it bumps `last_updated`, optionally flips `status`/`next_action`, emits trailers, commits, pushes. Don't reinvent the commit dance. When the work for a slug also touches sibling files (README, AGENTS.md, code under `bin/`), pass `--include=<path>` (repeatable) so the task file and the sibling change land in one commit with the right trailers. Full trigger rules + context-tight guidance: [docs/protocol.md](./docs/protocol.md#checkpoint-discipline--triggers).

**Autosave vs checkpoint — two layers, different verbs.** `bin/autosave.sh` is the **durability layer**: a slugless safety snapshot wired to Claude Code's PreCompact / SessionEnd hooks (per `bin/install-hooks.sh`) plus available for manual invocation. It exists so non-Claude agents (Codex CLI, Cursor, plain shell/vim) and Claude itself never lose work when context resets or sessions end. `bin/checkpoint.sh <slug>` is the **audit-trail layer**: per-slug, advances a single task's logical state, emits `Worklog-Slug:` + `Worklog-Status:` + other trailers. Autosave commits carry a `Worklog-Trigger: pre-compact | session-end | manual` trailer so `git log` consumers can filter (`bin/status.sh` already excludes autosave commits by default; pass `--include-meta` to surface them).

Autosave is not a "bypass" of per-slug discipline — it's the cross-agent portability layer that lets the protocol work outside Claude's hook ecosystem. The 20-40 autosave commits per month in this repo are the cost of multi-agent support, not noise.

## Derived caches

Worklog uses several derived caches under `.cache/` (gitignored — per-machine, regenerable from the vault). The contract:

- **Source of truth lives in git.** Every cache file is derivable from `people/*/{active,archive}/*.md` + git history. If a cache is deleted, the next helper invocation regenerates it.
- **Caches never cross machines.** `.cache/` is gitignored on purpose. Each clone builds its own from the synced vault — that's why "cross-machine drift" of caches is a non-issue.
- **Atomic write idiom.** Helpers that update caches write to a tempfile then `mv -f` to the final path, so concurrent same-machine sessions never see a half-written cache. This is the canonical KM/vault cache pattern (Obsidian's local indices follow the same shape).
- **Freshness is advisory.** Each cache carries a `# Stale after: <ISO>` header or a 1-hour-old-mtime fallback. Stale caches are silently skipped by readers, who fall through to the durable source.

| Cache | Producer | Consumer | Freshness |
|---|---|---|---|
| `.cache/compact-kernels.md` + `.json` | `bin/compact-kernels.sh` (PreCompact + SessionEnd hooks) | `/worklog init` preamble, fresh-session resume | 1h |
| `.cache/index.jsonl` | `bin/index.sh` | `bin/search.sh`, archive orphan-check | regenerated on demand |
| `.cache/index.embeddings.jsonl` | `bin/embed.sh` | `bin/search.sh --semantic` | rebuild explicitly |
| `.cache/claims/` (advisory mutex state) | `bin/_claim.py` via `bin/project.sh` | per-task claim arbitration | TTL per claim |
| `.cache/sessions/<sid>.json` | `bin/_lib.sh::resolve_session_id` | claim-holder identification in LOCKED_BY messages | session lifetime |

Two-session same-machine race on the same cache: the second writer wins; the first writer's state was already mirrored to the vault (caches are read-only from the vault's perspective). No cache stores authoritative state.

## Helpers

```bash
bin/checkpoint.sh <slug> [--status=X --next="..." --pr=N --rename=OLD --include=PATH ...]
bin/checkpoint-batch.sh < json                      # atomic multi-task checkpoint (one push for N flips)
bin/archive.sh    <slug> [--pr=N --reason="..."]
bin/autosave.sh                                    # safety snapshot (PreCompact/SessionEnd)
bin/status.sh     [--since=... --project=... --slug=... --format=json]
bin/context.sh    <slug> [--for=resume|review --format=json]
bin/init-scan.sh  [--ldap=<ldap> --format=json]    # exact Linear/Notion/PR seeds for init --full
bin/install-hooks.sh [--write --uninstall]         # wire autosave.sh as Claude Code PreCompact hook
bin/lint.sh       [--cross-task]                   # per-file format; --cross-task adds FSM/stale-review/undeclared-ref drift checks
bin/sql.sh        list|show|run|new <slug> <name>  # per-slug SQL library; runs via bq, response cache under .cache/queries/
bin/slug.sh       [--all] <fragment>               # closest-match slug lookup (exact / substring / Levenshtein)
bin/search.sh     <pattern> [--active --archive --kind= --status= --project= --linear= --pr= --repo= --ldap= --list --json --semantic --top=N]
bin/embed.sh      [--refresh --all]                # build .cache/index.embeddings.jsonl for --semantic search (fastembed, local-only)
bin/project.sh    new|next|claim|release|reap|verify|list   # multi-task projects with per-task advisory mutex
bin/task-guard.sh --slug=<slug> [--format=json]    # refuse to run when a foreign task file is dirty
bin/codex-surface-check.sh                         # README/AGENTS/local Codex skill command menu parity
```

### Per-slug SQL libraries — `queries/<slug>/<name>.sql`

Design docs that cite warehouse data should commit the queries that produced the numbers. Layout: `queries/<slug>/<name>.sql` (top-level `queries/` dir, NOT under `people/<ldap>/`). Required header: `-- @env: prod|staging` and `-- @description: <one-liner>`. Optional `-- @max-rows:` (default 1000).

**No literal PII in committed queries.** No email addresses, no long base64-shaped tokens (matches typical user_id / org_id encoding). Use `bq --parameter=name:STRING:value` if you need to scope by id at run time. `bin/sql.sh run` enforces both rules and refuses to execute on violation.

Response cache lives at `.cache/queries/<slug>/<name>.json` (gitignored). The cache means design-doc reviewers read the same numbers the author saw without re-running the query; force-refresh with `bin/sql.sh run <slug> <name> --no-cache`.

Cross-task lessons surfaced by shipped work live in [`docs/lessons.md`](./docs/lessons.md) — append a one-line entry when an archive produces a generalizable insight that future readers shouldn't have to re-derive from `git log`.

Each script self-documents via `--help`. Composition playbook: [docs/helpers.md](./docs/helpers.md).

## PR conventions (for event-driven checkpointing)

Source repos can automate worklog checkpoints via a GitHub Actions workflow
that listens on `pull_request` / `pull_request_review` events. The bot
uses the slug-as-join-key model (see top of file): it resolves a slug from
the PR, globs for the task file, writes a `Worklog-PR:` trailer. Order:

1. **`Worklog-Slug: <slug>` trailer in the PR body** — explicit override.
2. **Branch-name tail** — `<prefix>/<slug>` → `<slug>`. Works when your
   branch follows the `<ldap>/<slug>` convention.

The candidate is then looked up via `people/*/active/<slug>.md`. LDAP is
derived from the matched path — the bot does not trust GitHub login
(`ideogram-<ldap>`) or the branch prefix. If the glob doesn't match
**exactly one** file, the bot silently no-ops. Non-worklog users and PRs
never see worklog machinery on their PRs.

Status mapping (MVP; see `people/<ldap>/active/worklog-pr-event-hooks.md`
or its archived successor for rationale):

- `opened` / `reopened` → `in-review`, attach `pr:`
- `review_requested` → `in-review` (idempotent)
- review `changes_requested` → `in-progress`, `next_action = "address review on PR #N"`
- review `approved` / `commented` → no-op
- `closed` + `merged=true` → `shipping` (human still archives after deploy verify)
- `closed` + `merged=false` → no-op (human decides archive vs keep-open)

Bot commits are identifiable in `git log` by author `worklog-bot
<ldap@users.noreply.github.com>` — the name field distinguishes them from humans while
the email still routes to the right `people/<ldap>/` namespace for
`bin/status.sh --author=<ldap>` queries.

## Codex first-class `worklog` command

Claude Code has a real `/worklog` skill. Codex does not, so this repo
defines a **prompt-level equivalent**: when the user begins a message with
`worklog` followed by a supported subcommand, treat it as a first-class
command request, not as a question about the protocol.

Supported forms:

- `worklog help`
- `worklog init [--full]`
- `worklog sync [<slug>]`
- `worklog status [--since=... --slug=... --project=... --format=...]`
- `worklog context <slug> [--for=resume|review]`
- `worklog plan <task>` — emit a structured CoT/ToT/Reflexion plan block (paste-ready into a task body)
- `worklog spawn <task>` — emit a self-contained handoff prompt
- `worklog export` — write a sanitized setup artifact to `/tmp/worklog-setup-<ts>.txt` (shells out to `bin/export-setup.sh`, which is agent-agnostic)
- `worklog import <path>` — merge an export artifact into this machine's setup
- `worklog lint [--cross-task]` — validate task files; `--cross-task` adds drift checks
- `worklog review` — periodic protocol review; Codex uses `update_plan` for live tracking

Execution rules in Codex:

1. Run the corresponding `_worklog` workflow using the helper scripts in
   `bin/` plus the rules in this file.
2. Prefer doing the work over describing the work. If the user typed
   `worklog status`, produce the status update; don't reply with command
   documentation unless they asked "how does `worklog status` work?".
3. Preserve the command semantics Claude users expect:
   - `worklog init` — setup + LDAP resolution + read-only init scan
   - `worklog sync` — contextual save path: checkpoint, archive,
     backfill, or autosave based on repo reality (backfill definition:
     [docs/protocol.md § Backfill semantics](./docs/protocol.md#backfill-semantics))
   - `worklog status` — read-only standup/status synthesis
   - `worklog context` — single-task context pack
   - `worklog plan` — structured CoT/ToT/Reflexion plan block; pure generator, no preamble, no writes
   - `worklog spawn` — self-contained handoff prompt for a fresh session
   - `worklog export` / `worklog import` — round-trip setup across machines
     (both shell out to `bin/export-setup.sh` + the same awk-parsed artifact
     format Claude's skill uses; no Claude-specific deps)
   - `worklog lint` — `bin/lint.sh`, with optional `--cross-task`
   - `worklog review` — protocol review loop, with Codex `update_plan`
     replacing Claude `TaskCreate`
4. If flags are omitted, make the same reasonable-default choices a human
   would expect from the Claude workflow rather than erroring on missing
   optional arguments.
5. If the user is clearly asking for docs or implementation guidance
   about the command itself, answer normally instead of executing it.

## `init --full` external scan order

When doing a read-only full init scan across GitHub / Linear / Notion:

1. Start with `bin/init-scan.sh --format=json`. It emits exact IDs and URLs from active task files.
   - If it returns zero tasks, that is a normal cold-start state for a brand-new LDAP.
2. **Linear:** if a task has `linear:` or an `eng-<N>-` slug prefix, query the exact identifier first (`identifier: ENG-<N>`). Only fall back to semantic search when no exact ID exists.
3. **Notion:** if a task has flat `notion:` frontmatter or a Notion URL in body / `external_refs`, fetch that target directly. Do not semantic-search for a page when an exact page id or URL already exists.
4. **GitHub:** scan the PR numbers declared in frontmatter first, then authored open PRs in the repos named by the active tasks.
5. **De-dupe before proposing tasks:** for every Linear/Notion hit found during a cold-start outward scan, search GitHub for merged/closed PRs that mention the issue identifier, title keywords, or obvious workstream terms. If the work already landed, classify it as shipped evidence or project history — do not propose a new active task.

## Cold-start users

For a brand-new user / machine, the following are normal and should not be treated as setup failure:

- `_worklog` had to be cloned just now
- `people/<ldap>/` does not exist yet
- `bin/init-scan.sh` returns zero tasks
- `git log --author=<ldap>` returns no `_worklog` commits yet

In that state, treat `_worklog` as an empty journal and survey GitHub / Linear / Notion directly during `init --full`. The first pass is proposal-only: group discovered signals into candidate task files, show the grouping rationale and likely `next_action`, and wait for confirmation before writing. Do not fabricate task files just to make the repo non-empty; only create a task when there is concrete in-flight work to track and the user accepts the proposal.

**Unix philosophy — one script, one thing.** Don't bolt survey logic onto `checkpoint.sh`; don't teach `autosave.sh` to pick slugs. New responsibility → new script.

## Agent behavior defaults

- Terse updates; no trailing summaries unless asked.
- Surface tradeoffs before non-trivial implementation.
- Commit decisions — don't defer with "X if needed" wording.
- For exploratory questions: 2–3 sentence recommendation + tradeoff, not a plan dump.
- Never reply to human PR comments as the user.
- Verify state against reality (`git status`, `gh pr list`, `gt log`) before trusting worklog claims.
- **Standup / status-update asks get a 3–5 sentence prose synthesis**, not a `bin/status.sh` dump. Group shipped work by theme, not slug; name the work, not the PR number. Full rules: [docs/protocol.md § Standup synthesis](./docs/protocol.md#standup-synthesis--prose-not-a-dump).
