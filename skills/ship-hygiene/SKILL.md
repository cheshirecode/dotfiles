---
name: ship-hygiene
description: Pre-handoff / pre-EOW sweep across the surfaces that go stale together — worklog task bodies, open PR titles+bodies, PR stack CI/comment state, and post-merge cleanup readiness (worktree/branch/preview teardown notes). Use when the user says "tidy up before I ship", "PR hygiene", "clean my open PRs", "pre-handoff sweep", or invokes `/ship-hygiene`. Surfaces a dashboard, fixes only what's actually broken, prepares (does not run) post-merge teardown, and emits a single checkpoint at the end.
---

# ship-hygiene

A periodic sweep skill. Three surfaces share the same staleness pattern: a worklog task accumulates iteration drama; open PRs accumulate title typos / outdated bodies / bot-comment noise; the PR stack accumulates CI red and unresolved threads. Doing them all at once amortizes the context cost.

## When to use

- Pre-handoff (you're about to hand a stack off to a reviewer or a teammate)
- End-of-week clean-up
- After a multi-day spike where the worklog task body has grown 100+ lines
- User explicitly: "tidy my open PRs", "ship hygiene", "/ship-hygiene"

Skip if: only one PR open, body is short, no recent worklog activity. Overhead not earned.

## Surfaces + verbs

1. **Worklog task body** — `people/$LDAP/active/<slug>.md`. Verb: **compress**. Keep lessons, gotchas, decisions, re-runnable commands. Drop ToT/Reflexion/Assumptions sections once decided. Drop historical iteration tables — git log is the audit trail.
2. **Open PR titles+bodies + the diff's code comments** — `gh pr list --author @me --state open`. Verb: **audit, don't blind-edit**. Conv-Commit prefixes already correct? Body sized 1-4KB? Leave alone. Slop trigger: body >5KB with stale checklists, OR title missing prefix on a NEW PR (skip the fix on PRs older than a week — reviewers may have linked the original title). **Internal-reference purge (always):** PR title/body AND code comments are reviewer- and product-facing; strip leaked internal artifacts — worklog slugs/paths (`people/<ldap>/active/*`, `[POST-MERGE-CLEANUP]`, `next_action`), skill names (`/ship-hygiene`, `/impeccable`, `/worklog`), agent-process chatter ("Iteration 3", "per the audit", "scope chosen"), preview/worktree internals that don't help a reader understand the change. Keep the framing **external-facing and product-first** (what changed for users + why) **unless the change is a pure engineering/infra task** (refactor, codegen, tooling, migration) — then technical framing is fine, but the worklog/skill/agent-chatter purge still applies.
3. **PR stack health** — CI red, unresolved comments, missing approvals. Verb: **surface, not auto-fix**. Triage red checks by pattern (single shared failure across PRs = workflow config bug; per-PR unique failures = author work). Distinguish reviewer comments from bot noise (preview-deploy, lighthouse-ci, github-actions are bot signatures).
4. **Post-merge cleanup readiness** — the throwaway resources a PR leaves behind: its sibling worktree, its remote+local branch, and any live preview deploy. Verb: **prepare a note, never execute pre-merge**. For each open PR backed by these, emit the exact teardown commands and persist them as a `[POST-MERGE-CLEANUP]` note in the worklog task so they survive the merge and the next session. Running teardown while the PR is still open would kill the reviewer's preview and orphan the branch — only stage the note.

## Recipe

1. **Resolve which worklog task to clean.** Default: most-recently-touched active slug. Verify with `ls -t people/$LDAP/active/*.md | head -3`.
2. **Read it.** Slop trigger: **>150 lines AND the spike/decision is already made**. If shorter or still-active exploration, skip — leave the iteration drama until it's decided.
3. **Compress** if triggered. **Drop:** ToT/Reflexion scaffolding, multi-row iteration tables, "Assumptions to verify" once verified, redundant intermediate options. **Preserve:** final decision rationale, lessons/gotchas, re-runnable commands, frontmatter, `next_action`, open follow-up items.
4. **List open PRs:** `gh pr list --author @me --state open --repo <each-repo> --json number,title,reviewDecision,isDraft,updatedAt`.
5. **Per-PR dashboard:** for each non-draft PR, gather `body_length`, `failed_checks`, `pending_checks`, `comment_count`, last-comment-author. Print as a table.
6. **Title audit:** flag PRs missing Conv-Commit prefix OR with stale prefix (`frontend:` → `feat(spa):` style). **Do not edit titles on PRs older than 7 days** without explicit user confirmation.
7. **Body + comment audit:** flag PRs with body >5KB; read those bodies for stale checklists, ASCII art, duplicate context. Then scan for **internal-reference leaks** in (a) the title, (b) the body, and (c) code comments added by the diff: `gh pr diff <n> | grep -nE '^\+' | grep -iE 'worklog|\[POST-MERGE|next_action|/ship-hygiene|/impeccable|/worklog|people/[a-z]+/active|iteration [0-9]|per the (audit|critique)|scope chosen'`. For PR title/body, **fix in place** (it's your own reviewer-facing text — rewrite product-first, drop the internal refs). For **code comments**, surface them and fix only if they're genuinely leaked process notes; keep durable why-comments. Respect the pure-engineering exception (technical framing OK; internal-tooling chatter still goes).
8. **CI triage:** group failed checks by name. If the same check fails on N>1 PRs → systemic (workflow config bug, not per-PR). Surface the systemic finding as ONE actionable line.
9. **Comment triage:** check the last comment's author per PR. Bot signatures (`github-actions`, `vercel`, preview-deploy automation under the user's own login) → not unresolved review. Surface only PRs with a real reviewer comment that hasn't been responded to.
10. **Post-merge cleanup note:** for each open PR backed by a sibling worktree and/or a live preview, assemble the teardown commands and record them as a `[POST-MERGE-CLEANUP]` note in the worklog task (and surface them in the output). Discover the pieces: worktree via `git worktree list | grep <branch-slug>`; preview name from the branch slug / earlier deploy; services from the diff (`frontend`, `ui`, `admin-dashboard`). Template (do NOT run until the PR is merged):
    - preview: `make -C deployment/staging preview-cleanup-<svc> PREVIEW_NAME=<name>` (one per deployed service)
    - worktree: `git worktree remove <path>`
    - branch: usually auto-deleted on squash-merge; otherwise `git push origin --delete <branch>` + `git branch -D <branch>`
   If a `[POST-MERGE-CLEANUP]` note for this PR already exists, refresh it rather than duplicating.
11. **Checkpoint** the worklog body change(s): `WORKLOG_CHECKPOINT_FORCE=1 bin/checkpoint.sh <slug>`. Don't bundle unrelated working-tree changes.

## Output format

```
=== worklog tidy ===
  <slug>: N → M lines (-X%). Commit: <sha>

=== PR title/body audit ===
  N PRs scanned. M flagged for review (list). No blind edits applied.
  Internal-ref purge: <PRs whose title/body were de-internalized> · code comments: <clean | leaks at file:line>.

=== CI red ===
  <systemic finding if any>
  <per-PR red checks if not systemic>

=== Unresolved reviewer comments ===
  <PR + reviewer + 1-line context> per item.
  (N github-actions/CI/preview-link bot comments excluded — surface the count, don't silently drop.)

=== post-merge cleanup (prepare, do NOT run until merged) ===
  #<PR>: worktree <path> · branch <branch> · preview <name>
    make -C deployment/staging preview-cleanup-<svc> PREVIEW_NAME=<name>
    git worktree remove <path>
    git branch -D <branch>   # if not auto-deleted on merge
  Recorded as [POST-MERGE-CLEANUP] in <slug>.
```

## Anti-patterns to reject

- Blind-editing 20 PR titles for stylistic consistency — Conv-Commit minor variations are not slop.
- Rewriting PR bodies wholesale — they're the contract the reviewer agreed to read.
- Bundling unrelated worklog edits into the same checkpoint commit — breaks per-slug audit trail.
- "Resolving" reviewer threads by silently editing the PR body without acknowledging in a reply.
- Skipping the systemic-check triage step — fixing the same CI workflow bug per-PR wastes time.
- Running worktree/branch/preview teardown while the PR is still open — it kills the reviewer's preview and orphans the branch. Prepare the note; execute only after merge.
- Leaking internal artifacts into reviewer-facing text — worklog slugs, `[POST-MERGE-CLEANUP]`, skill names, "Iteration N", agent-process narration in a PR title/body or code comment. Strip them. Conversely, don't over-purge a pure-engineering PR into vague product-speak — keep it technically precise, just drop the internal-tooling chatter.

## Pairings

- `budget-mode` — apply during the worklog compress step. Terse prose, code untouched.
- `karpathy-guidelines` — apply during the PR title/body audit step. "Don't refactor what isn't broken" — most PRs need nothing.
- `systematic-debugging` — apply when CI red is per-PR (not systemic) to actually root-cause each failure.

## Examples

### Single sweep at end of long spike

```
User: /ship-hygiene
Claude: [identifies skillopt-setup as the slop-heavy task]
        [compresses 134 → 74 lines, commits]
        [scans 18 open PRs — all Conv-Commit clean]
        [surfaces 3-PR systemic CI workflow bug as a single line]
        [confirms no real reviewer comments need response]
        [single checkpoint commit, done]
```

### Empty case

```
User: /ship-hygiene
Claude: Nothing to do — worklog tasks all under 60 lines, no PRs flagged.
```
