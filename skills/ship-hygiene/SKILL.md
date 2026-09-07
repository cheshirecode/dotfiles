---
name: ship-hygiene
description: "Periodic multi-PR sweep — dashboard of open PRs across repos. Surfaces stale worklog tasks, CI red patterns, unresolved reviewer comments, post-merge cleanup notes. For single-PR code review or closeout, use $pr-review. Triggers 'tidy up before I ship', 'PR hygiene', 'clean my open PRs', '/ship-hygiene'."
---

# ship-hygiene

A periodic sweep skill. Three surfaces share the same staleness pattern: a worklog task accumulates iteration drama; open PRs accumulate title typos / outdated bodies / bot-comment noise; the PR stack accumulates CI red and unresolved threads. Doing them all at once amortizes the context cost.

**Delegates per-PR operations to `$pr-review`** (code review, self-check, closeout). This skill owns the **multi-PR dashboard sweep** only.

## Resolve `$WORKLOG_BIN`

This skill invokes worklog scripts via `$WORKLOG_BIN`. `worklog/SKILL.md` owns how to resolve it — follow it, don't restate it here.

## When to use

- Pre-handoff (you're about to hand a stack off to a reviewer or a teammate)
- End-of-week clean-up
- After a multi-day spike where the worklog task body has crossed 150 lines and the decision is already made
- User explicitly: "tidy my open PRs", "ship hygiene", "/ship-hygiene"

Skip if: only one PR open, body is short, no recent worklog activity. Overhead not earned.

## Surfaces + verbs

1. **Worklog task body** — `people/$LDAP/active/<slug>.md`. Verb: **compress**. Keep lessons, gotchas, decisions, re-runnable commands. Drop scaffolding once decided.
2. **Open PR titles+bodies** — aggregate across repos. Delegates per-PR deep analysis (title audit, body coherence, leak-scan) to `$pr-review` in review mode for each flagged PR.
3. **PR stack health** — CI red, unresolved comments, missing approvals. Verb: **surface, not auto-fix**. Triage systemic vs per-PR; distinguish reviewer comments from bot noise.
4. **Post-merge cleanup readiness** — worktree, branch, preview deploy. Verb: **prepare a note, never execute pre-merge**. Persist teardown commands as a `[POST-MERGE-CLEANUP]` note in the worklog task.

## Recipe

1. **Resolve which worklog task to clean.** Default: most-recently-touched active slug. Verify with `ls -t people/$LDAP/active/*.md | head -3`.
2. **Read it.** Slop trigger: **>150 lines AND the spike/decision is already made**. If shorter or still-active exploration, skip — leave the iteration drama until it's decided.
3. **Compress** if triggered. **Drop:** ToT/Reflexion scaffolding, multi-row iteration tables, "Assumptions to verify" once verified, redundant intermediate options. **Preserve:** final decision rationale, lessons/gotchas, re-runnable commands, frontmatter, `next_action`, open follow-up items.
4. **List open PRs** across all repos you contribute to. Use `gh pr list --author @me --state open --json number,title,reviewDecision,isDraft,updatedAt` (omit `--repo` for the default remote, or pass `--repo <owner/name>` for each additional repo).
5. **Per-PR dashboard:** for each non-draft PR, gather `body_length`, `failed_checks`, `pending_checks`, `comment_count`, last-comment-author. Print as a table.
6. **Flag suspicious PRs, then hand each one to `$pr-review`.** Flag on the
   dashboard signals only: a body over 5KB, a title with no Conv-Commit prefix,
   red CI, or an unanswered reviewer comment. Then invoke `$pr-review review #N`
   per flagged PR and let it run the deep checks — forge and ownership
   detection, leak-scan, title audit, body coherence, commit-set-to-title
   matching. Do not call pr-review's scripts by path: the two skills install
   into separate directories, so a relative path between them resolves only by
   accident.
7. **CI triage:** group failed checks by name. If the same check fails on N>1 PRs → systemic (workflow config bug, not per-PR). Surface the systemic finding as ONE actionable line.
8. **Comment triage:** check the last comment's author per PR. Bot signatures (`github-actions`, `vercel`, preview-deploy automation under the user's own login) → not unresolved review. Surface only PRs with a real reviewer comment that hasn't been responded to.
9. **Post-merge cleanup note:** for each open PR backed by a sibling worktree and/or a live preview, assemble the teardown commands and record them as a `[POST-MERGE-CLEANUP]` note in the worklog task (and surface them in the output). Discover the pieces: worktree via `git worktree list | grep <branch-slug>`; preview name from the branch slug / earlier deploy; services from the diff (`frontend`, `ui`, `admin-dashboard`). Template (do NOT run until the PR is merged):
     - preview: `make -C deployment/staging preview-cleanup-<svc> PREVIEW_NAME=<name>` (one per deployed service)
     - worktree: `git worktree remove <path>`
     - branch: usually auto-deleted on squash-merge; otherwise `git push origin --delete <branch>` + `git branch -D <branch>`
    If a `[POST-MERGE-CLEANUP]` note for this PR already exists, refresh it rather than duplicating.
10. **Checkpoint** the worklog body change(s): `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Don't bundle unrelated working-tree changes. Use the plain command — its staged-scope guard is what enforces that. `worklog/modes/sync.md` owns the guard's exit codes, `--include=<path>`, and the force bypass.

    **Hard failures** (nothing was committed — fix and re-run):
    - **exit 1** — staged paths outside the slug's scope. Re-run with `--include=<path>` for each path that belongs with this slug, or `git restore --staged <path>` for the ones that belong to a different commit.
    - **exit 2** — `--status=blocked` without a `Waiting on ...` next_action. Supply `--next="Waiting on <who or what>"`.

## Output format

```
=== worklog tidy ===
  <slug>: N → M lines (-X%). Commit: <sha>

=== PR dashboard (N scanned) ===
  #N  title                          body  CI-red  unres-comments  last_from
  #7  feat(upload): support s3       4KB   [x]     1               alice@
  #12 fix(ci): pin node@22           1KB   ok      0               bot(gha)

=== Systemic CI findings ===
  - build/docker: failing on 4+ PRs — likely workflow config bug, not per-PR

=== Unresolved reviewer comments ===
  #7: alice@ suggested renaming function — reply needed

=== post-merge cleanup (prepare, do NOT run until merged) ===
  #7: worktree <path> · branch <branch> · preview <name>
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

- `$pr-review` — delegates per-PR deep inspection (self-check, other-review, closeout). Ship-hygiene does NOT perform per-PR deslop itself anymore.
- `karpathy-guidelines` — apply during the title/body flagging step. "Don't refactor what isn't broken" — most PRs need nothing.
- For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

## Examples

### Single sweep at end of long spike

```
User: /ship-hygiene
Claude: [identifies skillopt-setup as the slop-heavy task]
        [compresses 168 → 84 lines, commits]
        [scans 18 open PRs — flags #7, #12, #15 for pr-review]
        [surfaces 3-PR systemic CI workflow bug as a single line]
        [confirms no real reviewer comments need response]
        [single checkpoint commit, done]
```

### Empty case

```
User: /ship-hygiene
Claude: Nothing to do — worklog tasks all under 150 lines (no compression triggered), no PRs flagged.
```
