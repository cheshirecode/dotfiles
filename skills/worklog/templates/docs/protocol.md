# Protocol — deep material

Root `AGENTS.md` holds the essentials every session needs on first read. This file holds the detail: edge cases, lifecycle diagrams, recipes. Read when the root doesn't answer the question at hand.

## Optional, pipeline-indexed frontmatter keys

Pipelines grep these; keep names stable. All are YAML scalars or flat lists (only `pr_repos` is a map).

| Key               | Type             | Use                                                                        |
| ----------------- | ---------------- | -------------------------------------------------------------------------- |
| `notion`          | page id          | design/RFC pointer                                                         |
| `pr`              | `[<n>, ...]`     | primary PR number(s); sibling stack PRs stay in body prose                 |
| `pr_repos`        | `{<n>: <repo>}`  | only when PRs span repos (rare; most tasks infer repo from `repos[0]`)     |
| `graphite_stack`  | branch name      | top of a `gt` stack                                                        |
| `reopens`         | slug             | re-opening an archived task (see FSM below)                                |
| `parent_slug`     | slug             | child → parent pointer; reverse is derived by grep                         |
| `related`         | list of maps     | peer links: `[{slug, note}]`, `note` required                              |
| `supersedes`      | slug             | replaces an abandoned approach (pair with `superseded_by` on the old task) |
| `superseded_by`   | slug             | set on the old task when a successor takes over                            |
| `external_refs`   | list of maps     | long-tail platform pointers — see below                                    |

### `external_refs` — long-tail platform pointers

For platforms that don't (yet) warrant a flat key: Slack threads, Figma files, GCP log queries, Amplitude charts, Sentry issues, Grafana boards, etc. Keep it a list of maps so pipelines can iterate without pattern-matching prose:

```yaml
external_refs:
  - platform: slack
    url: https://ideogram.slack.com/archives/C0XXXX/p17...
    note: design review thread
  - platform: figma
    url: https://figma.com/design/abc123/...?node-id=12-34
  - platform: gcp-logs
    url: https://console.cloud.google.com/logs/query;query=...
    note: error signature for the ENG-1514 rollout
  - platform: amplitude
    url: https://app.amplitude.com/analytics/ideogram/chart/xyz
```

Required per entry: `platform` (lowercase kebab), `url`. Optional: `note` (one line). No other keys — push extra context into the body.

**Recognized platform values** (canonical shapes — keep `url` exact so pipelines can join):

| `platform`   | `url` shape                                                            | Notes                                                                                       |
| ------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `slack`      | message permalink (`https://<workspace>.slack.com/archives/<C>/p<ts>`) | Encodes channel + thread parent. Used by `init --full` Slack tap-in to dedupe seen threads. |
| `figma`      | `https://figma.com/design/<fileKey>/...?node-id=<n>`                   | Frame-specific URLs preferred over file-root.                                               |
| `gcp-logs`   | `https://console.cloud.google.com/logs/query;query=...`                | Include the query string verbatim — that's the durable artifact.                            |
| `amplitude`  | `https://app.amplitude.com/analytics/<org>/chart/<id>`                 | —                                                                                           |
| `sentry`     | issue or query URL                                                     | —                                                                                           |
| `grafana`    | dashboard or panel URL                                                 | —                                                                                           |

Other platforms welcome — use a lowercase-kebab name and keep the URL canonical. Avoid creating near-duplicate slugs (e.g. `slack-thread` vs `slack`).

**Promotion path:** if a platform key appears in ≥30% of active tasks, promote it to a flat frontmatter key in the table above. Keep `external_refs` for the long tail; don't let it become a dumping ground for everything.

## Status lifecycle — full FSM

```
        ┌───────┐   start    ┌─────────────┐   open PR   ┌───────────┐
 new ──▶│ draft │───────────▶│ in-progress │────────────▶│ in-review │
        └───┬───┘            └──┬──▲────┬──┘             └──┬──▲──┬──┘
            │                   │  │    │                   │  │  │
            │                   │  │    │ blocked           │  │  │
         decline          unblock│ │    ▼                   │  │  │
            │                   │  │ ┌─────────┐            │  │  │
            │                   │  │ │ blocked │            │  │  │
            │                   │  │ └────┬────┘            │  │  │
            │                   │  │      │                 │  │  │
            │                   │  │      │ abandoned       │  │  │
            │                   │  └──────┤                 │  │  │
            │                   │         │   changes       │  │  │
            │                   │         │   requested     │  │  │
            │                   └─────────┼─────────────────┘  │  │
            │                             │                    │  │
            │                             │         approved + │  │
            │                             │         merged     │  │
            │                             │            ┌───────┘  │
            │                             │            │           │
            │                             │            ▼           │
            │                             │      ┌──────────┐      │
            │                             │      │ shipping │      │
            │                             │      └────┬─────┘      │
            │                             │           │            │
            │                             │           │ deploy +   │
            │                             │           │ verify     │
            ▼                             ▼           ▼            │
                              ┌──────────────────┐                 │
                              │  archived (TERM) │◀────────────────┘ upstream bug
                              └──────────────────┘                    surfaced in review
```

State meanings:

- **draft** — frontmatter exists; scope / plan may still be shifting. Includes `kind: proposal` tasks awaiting a decision.
- **in-progress** — actively coding or designing. The 95% state.
- **in-review** — PR (or design doc) is out for review. Reviewer feedback sends it back to `in-progress`.
- **blocked** — external dependency holds progress. On entry, rewrite `next_action` as `Waiting on <concrete thing>`. On exit, rewrite with the new concrete step.
- **shipping** — PR merged, deploy pending. Transition to `archived` only after deploy is confirmed.
- **archived** — **terminal**. Task is done-or-dropped and moved to `people/<ldap>/archive/`.

Archive reason is required and **enforced as an enum** by `bin/archive.sh --reason=...`. Allowed values:

```
shipped | declined | abandoned | superseded | merged | obsolete
```

Plus the special prefix `superseded by <slug>` for the pair-with-new-slug case. Any other value exits 2 with a listing of the allowed set. Historical archives with free-text reasons are grandfathered — the enum applies only to new archives.

On the archive commit, the script prepends one line to `## Context`:

```
Archived YYYY-MM-DD: <reason>: <body stays>.
```

Without this marker, outcomes are indistinguishable to anyone grepping later.

**`archived` is terminal.** Do not revive an archived task. If a regression or follow-up lands after archive, open a new task with a `reopens: <old-slug>` frontmatter key (additive per Liskov) so grep surfaces the chain.

Most commits are self-loops (same status, bumped `last_updated` / `next_action` / body). That is the normal case, not a transition.

**When in doubt, prefer fewer transitions.** If unsure between `in-progress` and `in-review`, stay in `in-progress` until the PR is explicitly handed off. If unsure between `in-review` and `shipping`, stay in `in-review` until merge. Status is coarse triage; PR-phase nuance belongs in `next_action` prose.

**Adding a new status requires the same scrutiny as the formalization above.** Six states is the budget; extending the FSM needs a concrete case the existing states can't express, not a nice-to-have.

## Kinds — detailed conventions

`kind:` is a grep-friendly tag for task class — a hint, not a schema gate. A task's `kind:` may add optional frontmatter keys (e.g., `notion:`, `pr:`, `incident:`) and body sections, but must never remove, rename, or override the required fields (`slug`, `status`, `repos`, `last_updated`, `next_action`) or the `## Context` / `## Next` sections. Any script or agent reading a task file must work uniformly across kinds.

Current kinds: `design | review | spike | impl | ops | debug | program | postmortem | runbook | proposal`. New kinds may be added ad hoc — same substitutability rule applies.

Extended ad-hoc kinds observed in the corpus (accepted by `bin/lint.sh`):

- `bugfix` — narrow fix for a known bug (distinct from `debug`, which includes reproduction).
- `investigation` — open-ended exploration without the time-box `spike` implies.
- `plan` — lightweight planning doc that isn't a full `design`/RFC.
- `infra` — ongoing infra work (distinct from one-shot `ops`).
- `cleanup` — refactor / tech-debt.

Legacy kinds — accepted but discouraged in new tasks (prefer canonical form):

- `bug` (use `debug` for investigation-included work, `bugfix` for narrow fixes).
- `perf` (use `impl` for feature-shaped perf work, `infra` for platform-shaped).
- `tooling` (use `infra`).

If you need a new kind, use it and add it to `KINDS` in `bin/_lint.py` plus this list. Do not let kinds proliferate without documentation.

**Archive entries with non-current kinds are silently grandfathered** (no warning). Archives are frozen history; rewriting them to satisfy a later taxonomy change is exactly what archives prevent. Active tasks still error on `kind` outside the documented set.

- `design` — one ADR/RFC/design doc (Google doc-first, Amazon 6-pager).
- `review` — bounded code/design review pass.
- `spike` — time-boxed investigation (Jira/agile).
- `impl` — feature/story implementation. May or may not be tracked in Linear; bare-slug `impl` tasks are fine.
- `ops` — one-shot infra/ops change.
- `debug` — reproducing + fixing a specific bug.
- `program` — multi-task stewardship: coordinates a design doc, Linear tickets, and iteration log across a phase/initiative (Amazon/Google "program"). Add sections for Linear hygiene and Iteration log.
- `postmortem` — incident RCA (Google SRE). Sections: timeline, root cause, action items, invariants lifted.
- `runbook` — repeatable ops procedure an agent can follow (Google SRE). Distinct from `ops` (one-shot) — runbooks are meant to be re-run.
- `proposal` — unrealized follow-on awaiting a decision. No code yet. Always paired with `status: draft`. See "Proposal tasks" below.

## Task file hygiene — signal vs. transient tooling noise

A task file is the cross-machine audit trail. Record durable outcomes; keep transient tooling state in the current session.

**Durable outcomes (record):**
- What shipped, landed, or was verified (path grid, status codes, upstream evidence, commit SHAs, deploy tags).
- Product-code failures surfaced *by* verification (e.g., carve-out returning 502, migration failing under load).
- Decisions with a one-line rationale. Commit to the decision; don't leave "X if needed" wording.
- Invariants that were confirmed or broken.

**Transient tooling noise (do not record):**
- Port-forward dropped, pod not ready, kubectl auth hiccup.
- `curl` timeout, DNS flake, flaky CI run on retry.
- Wrong secret path, wrong CF Access app, wrong context — in-session correction, not worklog content.
- Intermediate failed attempts that were later made to work. Record the final working path only.

**Why:** worklog drives "pick up where the last session left off." A task full of transient failures forces every future session to triage noise before finding signal. Keep the signal-to-noise ratio high.

**Edge case:** if the same tooling failure *recurs* across sessions or machines, it's no longer transient — promote it to a `reference` note (new memory or a `docs/` entry) describing the failure mode and fix. At that point it's a durable lesson, not a one-off hiccup.

### `next_action:` is a single-line pointer

`next_action:` in frontmatter is always a **single-line, double-quoted string** — a one-sentence summary of the next step. It is a *pointer*, not the decomposition.

- Multi-line `next_action: |` block scalars are rejected by `bin/lint.sh` — they break strict YAML once you include an unquoted `:` or indented list in the body.
- Checklists, substep breakdowns, and detailed plans live in the `## Next` body section.
- For `status: archived`, set `next_action: "—"`. Historical completion detail belongs in `## Completion notes` (or `## Context` / `## Outcome`) — never leave the ongoing plan dangling in the frontmatter of an archived file.
- When `bin/checkpoint.sh --next="..."` writes the value, it writes a plain string. Quote manually-edited `next_action:` values to keep strict YAML happy (`next_action: "Waiting on X"`), especially when the sentence contains `:` or leading `-`.

This discipline keeps `bin/_index.py` and every downstream jq query on a strict-YAML contract — no fallback parser, no surprises.

## Review-loop conventions (`kind: review`, `kind: design`)

Applies when running iterative review passes on a design doc, PR, or RFC (often via `/karpathy-guidelines` + `/budget-mode` loops).

- **Commit, don't hedge.** Replace conditional "split into X if needed" wording with the actual decision plus a one-line rationale. Conditional wording gets pushed back on.
- **Verify before claiming.** Confirm every file-path / line-number / API-surface claim against current code before asserting. Stale claims erode trust faster than no claim.
- **Bias toward fewer, higher-value edits per loop.** 2–4 sharp edits beats 10 nits. Flag remaining low-value gaps in the reply and ask whether to land them rather than silently piling on.
- **Each loop should produce new findings.** If a pass finds nothing substantive, say so and recommend stopping rather than fabricating work.
- **Decisions table is load-bearing.** When a design decision lands in prose, also land it in the doc's Decisions/Recommendations table — that's the first place a reviewer looks.
- **Inline review comments by default.** When posting PR review feedback, prefer line-anchored inline comments (`gh api repos/<owner>/<repo>/pulls/<n>/comments`) over a single prose review body. Each finding belongs on the line it applies to so the author can resolve threads independently. Use a top-level review body only for cross-cutting summary or score, not for findings that have a concrete file:line.
- **Defer Linear task creation** until explicitly asked. Design work comes first.

These are defaults, not hard rules. A review may justify 10 edits in one loop if the doc is early; adjust and say why.

## Cross-task references

When prose in one task file references another task, use the bare slug (`eng-1515-stack`, `pillbutton-style-merge`) verbatim so `grep -l '<slug>' people/*/active/*.md people/*/archive/*.md` surfaces related work. Agents reading a task may follow these mentions as pointers to avoid re-providing context.

For durable structural relationships, prefer frontmatter over prose so pipelines can index without parsing:

```yaml
parent_slug: landing-page-rebuild
related:
  - slug: eng-1514-website-prod-deployment
    note: prod mirror of the staging carve-out
supersedes: eng-1503-p17c-resolver-v4   # optional; abandoned alternative
```

Rules:

- Slugs are bare (no path, no `.md`). Every slug must resolve to a real file under `people/*/active/` or `people/*/archive/` at commit time.
- One direction only. Do not also write the reverse pointer on the other task — grep derives it.
- `note` is required on each `related` entry. Force the *why* into the file; "see also: <slug>" in prose is not sufficient.
- Prefer `parent_slug` over a prose breadcrumb when the relationship is durable (child of a `program`, follow-on from a design task, etc.). Transient mentions can stay in prose.
- `supersedes` / `superseded_by` is the symmetric pair for abandoned-approach replacement. Set `superseded_by` on the old task in the same commit that archives it; set `supersedes` on the successor.

## Proposal tasks (unrealized follow-ons)

Sometimes an idea surfaces mid-session — "we could also do X", a deferred expansion, a post-ship review note — that has no code yet. Capture it as its own task, not as a note buried inside the parent:

- `kind: proposal`, `status: draft`, `next_action` framed around the pending decision ("Decide scope, then implement").
- `## Context` opens with `Follow-on from <parent-slug>.` so grep surfaces the link.
- If the parent task is still active, append a `## Notes from <your-ldap>` block to the parent pointing at the new slug.
- Commit message: `<slug>: create (proposal)` so log readers can distinguish proposals from mid-flight work.

Agent contract: a task with `kind: proposal` means **awaiting a decision — do not start coding**. Treat it as read-only context until the user explicitly accepts or declines.

Why separate: proposals and in-progress work have different triage paths. Burying a proposal in the parent's body loses it to grep and to the `status` filter.

### Lifecycle: accept, decline, revise

A proposal has exactly three exits. Pick one and commit the transition atomically:

**Accept.** User green-lights implementation. In the same commit:
- Flip `kind: proposal` → the appropriate work kind.
- Flip `status: draft` → `in-progress`. Rewrite `next_action` as a concrete coding step.
- If more planning is needed before coding, accept to `kind: design` with `status: draft` first; transition to `kind: impl` + `status: in-progress` when coding actually starts. Keeps each state pure (never `impl` + `draft`).
- If the parent is still active, update the `## Notes from <your-ldap>` pointer from "proposed" to "accepted".
- Commit: `<slug>: accept (begin implementation)`.

**Decline.** Decision is "no" or "not now". In the same commit:
- Leave `kind: proposal`; flip `status: draft` → `archived`.
- Prepend the archive-reason line to `## Context`: `Archived YYYY-MM-DD: declined: <reason>.` The rest of the body stays intact — future agents searching for the same idea find the prior reasoning.
- If the parent is still active, either remove the `## Notes from <your-ldap>` pointer or update it to "declined <date>".
- `git mv people/<ldap>/active/<slug>.md people/<ldap>/archive/`.
- Commit: `<slug>: archive (declined)`.

**Revise.** Pre-decision refinement. Edit Context/Next freely; keep `kind: proposal`, `status: draft`. Regular `last_updated` bumps. No transition commit needed.

Never leave a proposal in `kind: proposal` after a decision has been made — the kind is the signal to other agents that no decision exists yet.

## Session protocol

### Session start

```bash
# from the worklog repo root (the kickoff prompt places you here)
git pull --no-rebase --autostash
ls people/<ldap>/active/
```

**Merge policy:** this repo preserves full linear history — `pull.rebase=false`, `pull.ff=true`. Pulls fast-forward when possible and create a merge commit when they can't. Never `git pull --rebase` or `git rebase` in `_worklog` (the skill configures the local repo on clone; don't override). Rationale: checkpoint commits are the audit trail; rewriting them loses the per-session signal.

**Single explicit exception — `bin/log-compact.sh`.** The compaction tool *does* rewrite history, by design, to fold same-slug `<slug>: checkpoint` bursts into one squashed commit per burst. Safety: dry-run is the default; `--apply` always tags `pre-compact-<timestamp>` first (preserved on origin) so original SHAs remain reachable. The tool refuses to run with a dirty tree or HEAD ahead of `origin/main`. Only valid while `_worklog/` has a single active committer; if a second active committer joins, the tool is closed and locked. See `worklog-log-compaction-squash`.

Read the task file(s) relevant to the job. **Verify state against reality** before acting — worklog files can be stale. Check `git status` / `gh pr list` / `gt log` in the target code repo.

### Full init external scan order

When an agent wants the richer `/worklog init --full` pass across GitHub / Linear / Notion, keep the scan deterministic:

1. Run `bin/init-scan.sh --format=json` to harvest exact targets from active task files.
   - If it returns zero tasks, that is a normal cold-start result for a new LDAP. Skip history-derived assumptions and survey external systems directly.
2. **Linear:** prefer exact identifier queries from `linear:` frontmatter or `eng-<N>-` slug prefixes (`identifier: ENG-<N>`). Use fuzzy semantic search only when no exact identifier exists.
3. **Notion:** prefer direct fetches from flat `notion:` frontmatter and any Notion URLs already present in the task body or `external_refs`. Semantic search is fallback-only.
4. **GitHub:** trust explicit `pr:` frontmatter first, then widen to authored open PRs in the repos named by the active tasks.
5. **Cold-start de-dupe:** before proposing a task from a Linear/Notion hit, search GitHub merged/closed PRs for the issue identifier, title keywords, and obvious workstream terms. If a PR already shipped the work, keep it as shipped evidence/project history instead of creating an active task candidate.

This ordering keeps `/worklog init --full` grounded in the task files instead of letting semantic search drift to similarly named tickets or pages. On a true cold start, `init --full` remains read-only and proposal-only: group external signals into candidate tasks, explain the grouping rationale, and wait for the human before writing files.

### Starting new work

```bash
$EDITOR people/<ldap>/active/<slug>.md   # write frontmatter + Context + Next
git add people/<ldap>/active/<slug>.md
git commit -m "<slug>: create"
git push
```

Push immediately so other machines see the task exists.

### Meaningful change (new PR, blocker, state flip)

Update frontmatter (`last_updated`, `next_action`, `status`) and body, then:

```bash
git add people/<ldap>/active/<slug>.md
git commit -m "<slug>: <what changed>"
git push
```

Commit messages should be specific: `eng-1515-stack: #11262 ready for review` beats `update`.

### Shipping

Shipping is a two-step transition, not a single move. `shipping` = PR merged, deploy pending. `archived` only after deploy/verify.

```bash
# Step 1 — when the PR merges
# Flip status: in-review → shipping. Rewrite next_action to the verify step.
# Commit as a self-loop checkpoint, file stays in active/.

# Step 2 — after deploy is verified (prefer bin/archive.sh):
bin/archive.sh <slug> --pr=<n>
```

Other archive reasons: `bin/archive.sh <slug> --reason="declined"` or `--reason="abandoned"`. `archived` is terminal — for a post-ship regression, open a new task with `reopens: <old-slug>`.

### Conflict handling

Push rejected? One other machine pushed first.

```bash
git pull --no-rebase
git push
```

Same-file conflict (rare, means two machines edited the same task): resolve the markdown conflict markers manually, preferring the newer `last_updated`. Commit the resolution.

**Discipline to avoid conflicts:** don't work the same task on two machines concurrently. One-file-per-task makes cross-task edits always mergeable.

## Checkpoint discipline — triggers

The worklog only works if task files get pushed before sessions end, compact, or lose context. Every agent must checkpoint at these triggers — **do not wait for the user to ask**:

1. **Verifiable progress.** A PR was opened/updated, a review arrived, a blocker was identified, `status` flipped, or `next_action` would now be wrong if someone else picked up the task. Checkpoint immediately.
2. **Context pressure.** When approaching compaction, long tool output, or a model summarization step — checkpoint first so state survives. Don't silently drop through.
3. **End of turn with uncommitted task edits.** If you edited a task file this turn, commit+push before yielding.
4. **User signals.** "checkpoint", "wrap up", "save state", "I'm switching machines" — checkpoint and confirm.
5. **Scope change.** User redirected you to a different task — checkpoint the old one first.

### When context feels tight and you're unsure what to save

Prefer asking the user once ("Checkpoint $slug now with status=$X?") over silently dropping progress. A short confirmation is cheaper than reconstructing state next session.

### Backfill semantics

`/worklog sync` (and `bin/checkpoint.sh` in `sync` mode) dispatches between four operations based on repo reality: `checkpoint`, `archive`, `backfill`, `autosave`. Backfill is the one without a dedicated script — it's the path the skill takes when there is concrete in-flight work (open PR, WIP branch, conversation-level progress) but **no task file exists yet**.

Trigger conditions for backfill:

- The user invoked `/worklog sync <slug>` or `/worklog sync` with an inferable slug.
- `people/<ldap>/active/<slug>.md` does not exist.
- There is evidence the work already happened — an open PR, a non-main branch, recent commits on the target repo, or durable decisions/progress that surfaced in conversation.

Procedure: create the task file from the available evidence (frontmatter + `## Context` citing the PR / branch / commit SHAs), set a single-line `next_action:`, then commit with the subject `<slug>: create (backfilled)`. The `(backfilled)` marker distinguishes backfilled files from same-session creates so `git log` stays a readable audit trail. Do **not** invent detail beyond what the evidence supports — backfill fills in the missing record, it doesn't reconstruct invariants the current session doesn't have.

## Standup synthesis — prose, not a dump

When the user asks for a "standup", "status update", or "what's going on", **synthesise** — don't paste `bin/status.sh` output. The script output is the raw material; the update is a 3–5 sentence prose summary shaped as:

1. **Done** — a single sentence naming the *work streams* that shipped (e.g. "marketing-intake overhaul, custom-models refactor, landing-page decouple"). Group by theme, not by slug. Never enumerate all 20 slugs.
2. **In review / in flight** — one sentence naming the open work by *what it does*, not by PR number. Use PR numbers only when they're the identifier someone would look up in Slack/GitHub; otherwise skip them.
3. **Blocked / parked** — one sentence per blocker, naming the task and the external dependency. Flag priority ("low priority, not on the critical path") when known; don't imply urgency that doesn't exist.
4. **Today's focus** — a clause, not a sentence: what you're actually landing next.

Style rules:

- **Work items, not PR counts.** "Shipped 20 today" is vanity; "shipped the marketing-intake overhaul and custom-models refactor" is signal.
- **Name the work.** A PR/slug identifier alone ("PR #58 is in review") tells the reader nothing. Lead with what the change does ("critical-path perf bundle"), then the identifier if useful.
- **Skip repetition.** If a slug is already implied by the work-stream ("marketing-intake overhaul" covers #39, #40, #47, #50), don't list the components.
- **Drop noise.** `next_action: "—"`, block-scalar leaks, archived rows, bare in-review slugs with no context — omit from the synthesis even if `bin/status.sh` surfaces them.
- **Inverted pyramid.** Most important first. A reader who stops after one sentence should still have the big picture.

Run `bin/status.sh` first to gather material; then write the synthesis. If you're unsure what the work-stream name is, read a couple of task files under `people/<ldap>/active/` before naming it.

## Surviving compaction

Long sessions degrade as the context window fills. Manual compaction (Claude Code `/compact`, or any LLM's "summarize and continue" equivalent) is the intervention, but its output is only as good as the context it summarized — summarize late and the model is already compressing a compressed view. The worklog absorbs this risk by moving the source of truth out of the conversation and into `people/<ldap>/active/<slug>.md`. Three layers, strongest first:

**1. Pre-compact durability — hook, not discipline.**

Claude Code's `PreCompact` + `SessionEnd` hooks run before the summary is written / session ends. Wire them to `bin/autosave.sh` + `bin/compact-kernels.sh` so (a) any dirty task-file edits land in git first, and (b) a per-active-task resume kernel dumps to `.cache/compact-kernels.md` — one small file that next session can read for all-task orientation instead of re-reading each task file.

```bash
bin/install-hooks.sh           # dry-run
bin/install-hooks.sh --write   # apply
```

The installer is idempotent and wires all four entries (PreCompact + SessionEnd × autosave.sh + compact-kernels.sh). Uninstall with `--uninstall --write`. Other LLM harnesses (Codex CLI, Cursor) have no equivalent hook — they run the scripts manually (see `docs/codex-setup.md`) and rehydrate from layer 3.

**2. Compact at ~60%, not at the warning.**

When the model warns, context has already been partially compressed — you're asking it to summarize a degraded view. Compact proactively, around 60% context utilization, while the view is still clean. Before running `/compact`:

1. `/worklog sync` (or `bin/checkpoint.sh <slug>`) — push current state so the file, not the conversation, holds it.
2. Run `/compact` with the worklog-aware instruction:

    ```bash
    /compact $(cat docs/compact-instruction.md)
    ```

    The template ([docs/compact-instruction.md](./compact-instruction.md)) anchors on active slug, `next_action:`, last pushed SHA, open PRs, mid-debug state. It explicitly tells the model to drop tool transcripts and resolved tangents and to point at the task file rather than re-embed its content.

Keep the instruction short — five to ten anchors at most. A three-paragraph preservation prompt defeats compaction.

**3. Post-compact rehydration — the file wins.**

Whether compaction was manual, automatic, or you're resuming on a new machine, the first action is the same. Check `.cache/compact-kernels.md` with the 1h mtime gate defined in [AGENTS.md § Surviving compaction](../AGENTS.md#surviving-compaction) — that snippet is the canonical form; don't re-inline it here. The file self-describes its freshness via a `# Stale after: <ISO>` header as a secondary cue. If the gate passes, the kernel gives you all active tasks' state in ~7 lines each; if stale (>1h) or absent, fall through to per-task reads:

```bash
bin/status.sh --slug=<slug>
$EDITOR people/<ldap>/active/<slug>.md   # or whatever read tool
```

Read the task file before acting. State the slug + `next_action:` back to the user as a verification check. If the compact summary disagrees with the file, the file wins — update the summary, not the file.

Multi-compact sessions: the file accumulates across compactions. No rewrite needed; the same three layers apply to the next window.

## Commit trailers — examples and body

### Examples

Self-loop checkpoint (no state change):
```
eng-1515-stack: matrix +7 rows (38→45) on #11257 b2c7ec0763
```

Status transition (blocked):
```
eng-1514-website-prod-deployment: block on ENG-1514 prod deploy identity

Waiting on ENG-1514 DNS confirmation — can't draft deployment/production/ without it.

Worklog-Status: blocked
```

Task creation without a Linear ID (bare slug — first-class, not provisional):
```
amplitude-gcp-log-correlation: create (design doc exists; impl TODO)

Worklog-Status: draft
Worklog-Kind: impl
```

Task creation with a Linear ID at creation time:
```
eng-1621-amplitude-gcp-log-correlation: create

Worklog-Status: draft
Worklog-Kind: impl
Worklog-Linear: ENG-1621
```

Optional retroactive rename if a Linear ID later becomes useful for cross-referencing:
```
eng-1621-amplitude-gcp-log-correlation: rename (Linear ticket filed)

Worklog-Previous-Slug: amplitude-gcp-log-correlation
```

### Body convention

Checkpoint commits include the current `next_action` as a one-line body prefixed `next: ` so `git log --format=%b` gives a readable "what's next per slug" view without opening each task file. Manual commits should follow the same convention for consistency.

### Noise filter

Skip `autosave:` and `protocol:` / `bin:` / `docs:` subjects in per-user activity summaries — snapshot or meta commits, not task work:

```bash
git log --since=yesterday --author="<ldap>@" \
  --invert-grep --grep='^\(autosave\|protocol\|bin\|docs\)\b'
```

### Daily-summary recipe

```bash
# Tasks you touched since yesterday, with state flips and what's next:
git log --since=yesterday --author="<ldap>@" \
  --invert-grep --grep='^\(autosave\|protocol\|bin\|docs\)\b' \
  --format='%s%n  %b%n  status=%(trailers:key=Worklog-Status,valueonly)%n  pr=%(trailers:key=Worklog-PR,valueonly)%n'

# Single task's history (follows renames via Worklog-Previous-Slug trailer):
git log --all --grep='^<slug>:' --grep='Worklog-Previous-Slug: <slug>$' --regexp-ignore-case
```

Or prefer `bin/status.sh --since=yesterday` / `bin/status.sh --slug=<slug>`.

## Frontend environment notes (`website`, `ui/frontend/react`)

### Node on macOS — avoid Codex.app's bundled node

Some Claude/Codex host apps ship their own `node` at `/Applications/Codex.app/Contents/Resources/node`. When `node` resolves there, `require()`-ing any third-party native `.node` binary (rollup, sharp, esbuild, etc.) fails with:

> `dlopen ... code signature ... not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs`

macOS blocks loading native binaries whose signing team doesn't match the host process. Reinstalling doesn't fix it — the host binary is the wrong one. Symptoms: `npm run lint` / `npm run build` / `npm run dev` explode inside rollup or vite on any Astro/Vite/Vitest project.

**Fix — use the system/user-installed node, not the host app's:**

- Preferred: start the shell with your login config so `nvm` / Homebrew paths land first. `zsh -l` or `bash -l` in the session preamble; or `source ~/.zshrc` (or `~/.bash_profile`) before the first npm command.
- Quick one-off: prefix the command — `PATH=/opt/homebrew/bin:$PATH npm run <script>`.
- Verify with `which node`; if it resolves under `/Applications/Codex.app/...`, you're on the wrong one.

Applies to any pre-commit / pre-push hook that runs `astro check`, `vite build`, or similar — fix the PATH before the hook runs or the commit/push will fail.

## Query examples

Prefer `bin/*.sh` helpers for structured queries; fall back to `rg` (ripgrep) for ad-hoc interactive searches and `grep` when staying POSIX-only (e.g. inside `bin/*`).

```bash
# Structured (derivative index — auto-rebuilds when stale):
bin/children.sh eng-1515-stack --include-refs      # children, related[], body mentions
bin/pr.sh 11262                                    # tasks referencing PR #11262
bin/stale.sh --days=14                             # active tasks gone stale
bin/lint.sh                                        # validate every frontmatter (rules below)
bin/status.sh --slug=eng-1515-stack                # per-slug chronological history

# Ad-hoc — ripgrep (preferred; smart case, gitignore-aware, --type md, --json):
rg --type md '^status: blocked' people/
rg --type md '^status: in-review' people/$LDAP/active/
rg --type md -l '\bui\b' people/$LDAP/active/ | xargs rg --type md '^repos:'

# POSIX fallback — grep (for contexts without rg):
grep -l '^status: blocked' people/*/active/*.md
grep -l '^status: in-review' people/$LDAP/active/*.md
git log --oneline -20 people/$LDAP/active/       # recent activity
```

`rg` is recommended for interactive use but is **not** a runtime dependency of `bin/*` — those scripts stay on `python3` / `grep` / `awk` / `jq` so the repo runs on a bare POSIX + Python machine (see `docs/helpers.md § Query tools`).

## Lint rules

`bin/lint.sh` (shell wrapper around `bin/_lint.py`) validates every task file under `people/*/{active,archive}/`. Scope is **per-file structural validation** — not cross-file invariants.

Errors (exit 1):

- Frontmatter block exists and parses as strict YAML.
- `slug` present and matches the grammar `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`.
- `kind` present and in the documented set (see Kinds — detailed conventions).
- `status` present and in the FSM (`draft | in-progress | in-review | blocked | shipping | archived`).
- `last_updated` present and matches `YYYY-MM-DD`.
- `next_action` present and a single-line string — multi-line block scalars (`|`) are rejected because they break strict YAML once a body contains `:` or indented lists.
- `repos` absent or a list.
- `project` absent, `"none"`, or lowercase-kebab.
- Relations (`parent_slug`, `supersedes`, `superseded_by`, `reopens`, each `related[].slug`) resolve to a real task file under `people/*/{active,archive}/`.
- Every `related[]` entry has a `note` (one-line *why*; required to prevent link rot).
- A file under `active/` must not have `status: archived`.

Warnings (exit 0):

- Missing `project:` on an active task (suggest `none` if intentional).
- File under `archive/` without `status: archived`.

Out of scope: slug uniqueness (collisions surface at glob time — see AGENTS.md § Slug as join key), link-rot against Linear/Notion/GitHub.

### Cross-task checks (`--cross-task`)

`bin/lint.sh --cross-task` adds protocol-drift checks across active tasks. Opt-in (not run by hooks). Errors and warnings are additive on top of the per-file mode.

Active tasks only — archive/ is frozen history.

Errors:

- `status: blocked` requires `next_action` to start with `Waiting on` (FSM contract from AGENTS.md § Status lifecycle).

Warnings:

- `status: in-review` for ≥14 days with no `Worklog-PR:` trailer in `git log` for the slug — PR likely landed/abandoned without a status flip.
- Body mentions a known slug not declared in `parent_slug` / `related[].slug` / `supersedes` / `superseded_by` / `reopens` — undeclared cross-task reference, link-rot precursor. The match is narrow: only literal-slug tokens that resolve to a real task file (kebab tokens that don't resolve are ignored to avoid false positives on prose).

When to run: before archiving a task, after a long session, or weekly. Not wired into a hook because the warnings are heuristic and require human judgment to act on.

### Auto-stub missing `related:` (`--fix-related`)

`bin/lint.sh --fix-related` is the auto-fix companion to the body-mention warning above. It scans each active task's body for known sibling slugs not declared in any relation field, and appends them to the file's `related:` block with a placeholder note (`"(auto-added; refine note)"`). Implies `--cross-task`. Refuses to touch files where `related:` is in inline-list form.

The flow: write the body referencing whatever sibling slugs the prose calls for, run `bin/lint.sh --fix-related`, then refine the placeholder notes to describe the actual relation. Removes the friction of manually mirroring body content into structured frontmatter every time you mention a sibling slug.

## Drift surfaces

Doc-code drift is the dominant maintenance bug class in this repo (per `docs/lessons.md`). The surfaces below are where it tends to land. Each row records what's authoritative, what mirrors it, and whether `bin/git-hooks/pre-commit` carries an advisory check.

| ID | Surface | Authoritative | Mirror(s) | Pre-commit check |
|---|---|---|---|---|
| D1 | `KINDS` taxonomy | `bin/_lint.py:KINDS` | `docs/protocol.md § Kinds` | none (markdown parsing too brittle) |
| D2 | Status FSM | `bin/_lint.py:STATUSES` | `docs/protocol.md § Status lifecycle`, `AGENTS.md` | none |
| D3 | `bin/*` script mentions | the script itself | `docs/helpers.md`, `AGENTS.md`, `README.md` | **advisory** — nudge if `bin/X.{sh,py}` staged but no doc file staged and `X` is referenced in docs |
| D4 | Skill mode list | `~/.claude/skills/worklog/modes/*.md` | `SKILL.md` description / table | n/a (out of worklog repo) |
| D5 | Scrubber regex parity | `bin/export-setup.sh:scrub()` | `tests/export/test_scrubber.sh` | **advisory** — diff the secret-regex sets when either side staged |
| D6 | Frontmatter shape | `AGENTS.md` + `docs/protocol.md § Task file format` | `bin/_lint.py` validators | none (heterogeneous) |
| D7 | `--help` text vs prose | `bin/<script>.sh --help` | `docs/helpers.md` prose | none (free text) |
| D8 | CI workflow citations | `.github/workflows/*.yml` files | doc prose | **advisory** — grep prose for `.github/workflows/X.yml` cited but missing from disk |
| D9 | Shell + Python portability | scripts under `bin/` (audited script-level for macOS BSD vs Linux GNU vs Linux musl) | none — no second authoritative copy | **manual** — `bin/e2e-docker.sh` runs the full helper-set against debian-slim and alpine images. Not in pre-commit (build cost too high); invoke before pushing changes that touch `bin/*.sh`, `bin/*.py`, `bin/git-hooks/*`, `tests/*`, or `Dockerfile*` |

Advisory means "warn on stderr, never block." Bypass with `WORKLOG_NO_HOOK=1`. Add a new row before extending the hook so the rationale lives next to the catalog.

## Prompt-cache alignment (for agent authors)

The `worklog` skill is organized as a **thin router** (`~/.claude/skills/worklog/SKILL.md`, ~75 lines) plus **on-demand mode files** (`modes/<mode>.md`, loaded only when that mode is invoked). This layout is prompt-cache-friendly on providers with a prefix-cache TTL (Anthropic's is 5 minutes):

1. **Static content first, user input last.** The router + AGENTS.md (when loaded) sit at the front of the session; user arguments and tool results accumulate after. Repeat invocations within the TTL hit the static prefix.
2. **Don't inline mode detail into SKILL.md.** A fat single-file skill loads all seven modes' prose on every `/worklog` call — wasted tokens and a bigger prefix to invalidate on any edit.
3. **Don't re-read AGENTS.md mid-session.** The preamble table gates reads by mode; when the agent already loaded it earlier in the turn, skip it.
4. **Small edits to frequently-loaded files are expensive.** Every edit to `SKILL.md` or `AGENTS.md` invalidates the cache for the next hour of sessions. Batch edits; avoid cosmetic churn.

If a future contributor is tempted to re-inline mode files "for simplicity," the payback is ~7× more tokens loaded per invocation (measured pre-slim: 501 vs. 75 lines for the router). The split is load-bearing, not a preference.
