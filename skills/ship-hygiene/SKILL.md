---
name: ship-hygiene
description: Sweep surfaces that go stale together — worklog task bodies, open PR titles+bodies, PR stack CI/comments, post-merge cleanup notes. Triggers "tidy up before I ship", "PR hygiene", "clean my open PRs", "pre-handoff sweep", `/ship-hygiene`. Surfaces a dashboard, fixes only what's broken, never runs post-merge teardown pre-merge.
---

# ship-hygiene

A periodic sweep skill. Three surfaces share the same staleness pattern: a worklog task accumulates iteration drama; open PRs accumulate title typos / outdated bodies / bot-comment noise; the PR stack accumulates CI red and unresolved threads. Doing them all at once amortizes the context cost.

## Resolve `$WORKLOG_BIN`

This skill invokes worklog scripts via `$WORKLOG_BIN`. Resolve it the same way the worklog skill does:

```bash
WORKLOG_BIN="${WORKLOG_BIN:-$HOME/.claude/skills/worklog/bin}"
```

All `checkpoint.sh` references below use this variable.

## When to use

- Pre-handoff (you're about to hand a stack off to a reviewer or a teammate)
- End-of-week clean-up
- After a multi-day spike where the worklog task body has crossed 150 lines and the decision is already made
- User explicitly: "tidy my open PRs", "ship hygiene", "/ship-hygiene"

Skip if: only one PR open, body is short, no recent worklog activity. Overhead not earned.

## Surfaces + verbs

1. **Worklog task body** — `people/$LDAP/active/<slug>.md`. Verb: **compress**. Keep lessons, gotchas, decisions, re-runnable commands. Drop scaffolding once decided.
2. **Open PR titles+bodies + code comments** — `gh pr list --author @me --state open`. Verb: **audit, don't blind-edit**. Slop triggers: body >5KB with stale checklists, title missing Conv-Commit prefix on a new PR. Always: **purge internal-reference leaks** (worklog paths, `[POST-MERGE-CLEANUP]`, `next_action`, agent-process chatter, skill command names unless the PR changes skill files). Keep framing product-first unless it's a pure engineering task.
3. **PR stack health** — CI red, unresolved comments, missing approvals. Verb: **surface, not auto-fix**. Triage systemic vs per-PR; distinguish reviewer comments from bot noise.
4. **Post-merge cleanup readiness** — worktree, branch, preview deploy. Verb: **prepare a note, never execute pre-merge**. Persist teardown commands as a `[POST-MERGE-CLEANUP]` note in the worklog task.

## Recipe

1. **Resolve which worklog task to clean.** Default: most-recently-touched active slug. Verify with `ls -t people/$LDAP/active/*.md | head -3`.
2. **Read it.** Slop trigger: **>150 lines AND the spike/decision is already made**. If shorter or still-active exploration, skip — leave the iteration drama until it's decided.
3. **Compress** if triggered. **Drop:** ToT/Reflexion scaffolding, multi-row iteration tables, "Assumptions to verify" once verified, redundant intermediate options. **Preserve:** final decision rationale, lessons/gotchas, re-runnable commands, frontmatter, `next_action`, open follow-up items.
4. **List open PRs:** run `gh pr list --author @me --state open --json number,title,reviewDecision,isDraft,updatedAt` once per repo you contribute to (omit `--repo` for the default remote, or pass `--repo <owner/name>` for each additional repo).
5. **Per-PR dashboard:** for each non-draft PR, gather `body_length`, `failed_checks`, `pending_checks`, `comment_count`, last-comment-author. Print as a table.
6. **Title audit:** flag PRs missing Conv-Commit prefix OR with stale prefix (`frontend:` → `feat(spa):` style). **Do not edit titles on PRs older than 7 days** without explicit user confirmation.
7. **Body + comment audit** — three sub-steps, run in order:

   **7a. Size flag.** PRs with body >5KB: read for stale checklists, ASCII art, duplicate context.

   **7b. Internal-ref leak scan.** Run both greps below — they are not redundant (a worklog path in the diff is a leaked *code comment*; the same string in the body is a leaked *PR description*; a body under 5KB skips the size flag but still needs this scan):
   - Title + body: `gh pr view <n> --json title,body -q '.title + "\n" + .body' | grep -inE 'worklog:|\[POST-MERGE|next_action|/ship-hygiene|/worklog|people/[A-Za-z0-9._-]+/active|iteration [0-9]|per the (audit|critique)|scope chosen'`
   - Code comments (added lines only): `gh pr diff <n> | grep -nE '^\+' | grep -iE 'worklog:|\[POST-MERGE|next_action|/ship-hygiene|/worklog|people/[A-Za-z0-9._-]+/active|iteration [0-9]|per the (audit|critique)|scope chosen'`

   **7c. Fix.** For title/body: **fix in place** — rewrite product-first, drop the internal refs. For code comments: surface and fix only if genuinely leaked process notes; keep durable why-comments.

   **Leak-token notes:**
   - The token is `worklog:` (the trailer form), not bare `worklog` — a PR describing worklog *tooling* uses "worklog" as product vocabulary. The leaked forms (`Worklog:` trailer, worklog *paths*) are still caught (the latter by `people/[A-Za-z0-9._-]+/active`, which matches dotted/hyphenated/numeric LDAPs such as `people/fred.tran/active/...`).
   - If the PR changes `skills/**`, `manifest/skills.yaml`, or skill docs: allow the relevant skill command names; still purge worklog paths, `next_action`, and agent-process chatter.
   - Pure-engineering exception: technical framing is fine; internal-tooling chatter still goes.
8. **CI triage:** group failed checks by name. If the same check fails on N>1 PRs → systemic (workflow config bug, not per-PR). Surface the systemic finding as ONE actionable line.
9. **Comment triage:** check the last comment's author per PR. Bot signatures (`github-actions`, `vercel`, preview-deploy automation under the user's own login) → not unresolved review. Surface only PRs with a real reviewer comment that hasn't been responded to.
10. **Post-merge cleanup note:** for each open PR backed by a sibling worktree and/or a live preview, assemble the teardown commands and record them as a `[POST-MERGE-CLEANUP]` note in the worklog task (and surface them in the output). Discover the pieces: worktree via `git worktree list | grep <branch-slug>`; preview name from the branch slug / earlier deploy; services from the diff (`frontend`, `ui`, `admin-dashboard`). Template (do NOT run until the PR is merged):
    - preview: `make -C deployment/staging preview-cleanup-<svc> PREVIEW_NAME=<name>` (one per deployed service)
    - worktree: `git worktree remove <path>`
    - branch: usually auto-deleted on squash-merge; otherwise `git push origin --delete <branch>` + `git branch -D <branch>`
   If a `[POST-MERGE-CLEANUP]` note for this PR already exists, refresh it rather than duplicating.
11. **Checkpoint** the worklog body change(s): `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Don't bundle unrelated working-tree changes. If a sibling path genuinely belongs to this slug, add it with `--include=<path>` (repeatable) — that is the sanctioned scoped mechanism and the one checkpoint.sh itself recommends. `WORKLOG_CHECKPOINT_FORCE=1` is the blunt last resort: use it only as an explicit, stated-reason override; default ship-hygiene must preserve the staged-scope guard.

    **Hard failures** (nothing was committed — fix and re-run):
    - **exit 1** — staged paths outside the slug's scope. Re-run with `--include=<path>` for each path that belongs with this slug, or `git restore --staged <path>` for the ones that belong to a different commit.
    - **exit 2** — `--status=blocked` without a `Waiting on ...` next_action. Supply `--next="Waiting on <who or what>"`.

## Output format

```
=== worklog tidy ===
  <slug>: N → M lines (-X%). Commit: <sha>

=== PR title/body audit ===
  N PRs scanned. M flagged for review (list). Blind edits: none. Internal-ref cleanup: <none | PRs updated>.
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

- `karpathy-guidelines` — apply during the PR title/body audit step. "Don't refactor what isn't broken" — most PRs need nothing.
- For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

## Examples

### Single sweep at end of long spike

```
User: /ship-hygiene
Claude: [identifies skillopt-setup as the slop-heavy task]
        [compresses 168 → 84 lines, commits]
        [scans 18 open PRs — all Conv-Commit clean]
        [surfaces 3-PR systemic CI workflow bug as a single line]
        [confirms no real reviewer comments need response]
        [single checkpoint commit, done]
```

### Empty case

```
User: /ship-hygiene
Claude: Nothing to do — worklog tasks all under 150 lines (no compression triggered), no PRs flagged.
```
