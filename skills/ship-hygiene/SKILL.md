---
name: ship-hygiene
description: "Periodic multi-PR sweep — dashboard of open PRs across repos. Surfaces stale worklog tasks, CI red patterns, unresolved reviewer comments, post-merge cleanup notes. For single-PR code review or closeout, use $pr-review. Triggers 'tidy up before I ship', 'PR hygiene', 'clean my open PRs', '/ship-hygiene'."
---

# ship-hygiene

`bin/leak-scan.sh` is a compatibility launcher requiring installed `pr-review`; the scanner and token list live there.

This skill owns the multi-PR dashboard. `$pr-review` owns individual reviews
and closeouts. Flag suspicious PRs here; let that skill inspect them.

## Resolve `$WORKLOG_BIN`

This skill invokes worklog scripts via `$WORKLOG_BIN`. `worklog/SKILL.md` owns how to resolve it — follow it, don't restate it here.

## When to use

- Pre-handoff (you're about to hand a stack off to a reviewer or a teammate)
- End-of-week clean-up
- After a multi-day spike where the worklog task body has crossed 150 lines and the decision is already made
- User explicitly: "tidy my open PRs", "ship hygiene", "/ship-hygiene"

Skip if: only one PR open, body is short, no recent worklog activity. Overhead not earned.

Surface CI failures, unresolved review, and missing approvals; do not auto-fix
them. Prepare cleanup notes only; never tear down an open PR's resources.

## Recipe

1. **Resolve which worklog task to clean.** Use the named task or a task linked to the current repo/PR. Recency is only a discovery hint; verify ownership and relevance before editing. If no task is identified, skip compression and continue the PR sweep.
2. **Read it.** Slop trigger: **>150 lines AND the spike/decision is already made**. If shorter or still-active exploration, skip — leave the iteration drama until it's decided.
3. **Compress** if triggered. **Drop:** ToT/Reflexion scaffolding, multi-row iteration tables, "Assumptions to verify" once verified, redundant intermediate options. **Preserve:** final decision rationale, lessons/gotchas, re-runnable commands, frontmatter, `next_action`, open follow-up items.
4. **List open PRs** across all repos you contribute to. Use `gh pr list --author @me --state open --json number,title,reviewDecision,isDraft,updatedAt` (omit `--repo` for the default remote, or pass `--repo <owner/name>` for each additional repo).
5. **Per-PR dashboard:** for each non-draft PR, gather `body_length`, `failed_checks`, `pending_checks`, `comment_count`, last-comment-author. Print as a table.
6. **Flag suspicious PRs, then hand each one to `$pr-review`.** Flag on the
   dashboard signals only: a body over 5KB, a title with no Conv-Commit prefix,
   red CI, or an unanswered reviewer comment. Then invoke `$pr-review review #N`
   per flagged PR. Do not call pr-review's scripts by path: the two skills install
   into separate directories, so a relative path between them resolves only by
   accident.
7. **CI triage:** group failed checks by name. If the same check fails on N>1 PRs, inspect logs for a shared cause before calling it systemic. Group a confirmed shared cause into one actionable line.
8. **Comment triage:** check the last comment's author per PR. Bot signatures (`github-actions`, `vercel`, preview-deploy automation under the user's own login) → not unresolved review. Surface only PRs with a real reviewer comment that hasn't been responded to.
9. **Post-merge cleanup note:** for each open PR backed by a sibling worktree and/or a live preview, assemble the teardown commands and record them as a `[POST-MERGE-CLEANUP]` note in the worklog task (and surface them in the output). Discover the pieces: worktree via `git worktree list | grep <branch-slug>`; preview name from the branch slug / earlier deploy; services from the diff (`frontend`, `ui`, `admin-dashboard`). Template (do NOT run until the PR is merged):
     - preview: `make -C deployment/staging preview-cleanup-<svc> PREVIEW_NAME=<name>` (one per deployed service)
     - worktree: `git worktree remove <path>`
     - branch: usually auto-deleted on squash-merge; otherwise `git push origin --delete <branch>` + `git branch -D <branch>`
    If no relevant Worklog task was identified, include the note only in the report. Otherwise refresh an existing `[POST-MERGE-CLEANUP]` note for this PR rather than duplicating it.
10. **Checkpoint** the worklog body change(s): `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Don't bundle unrelated working-tree changes. Use the plain command — its staged-scope guard is what enforces that. `worklog/modes/sync.md` owns the guard's exit codes, `--include=<path>`, and the force bypass.

    On a non-zero exit, read Worklog’s `modes/sync.md` checkpoint failure rules before retrying; do not report a refused checkpoint as saved.

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

## Boundaries

Do not rewrite PR titles/bodies for stylistic consistency or treat a body edit
as a reply to a reviewer. Keep reviewer-facing text technically precise and
free of internal Worklog/skill/process details. Posting messages requires
authorization already given in the conversation or obtained before posting.

## Pairings

- `karpathy-guidelines` — apply during the title/body flagging step. "Don't refactor what isn't broken" — most PRs need nothing.
- For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.
