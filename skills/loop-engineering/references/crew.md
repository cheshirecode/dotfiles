# Crew mode — parallel worker sessions

Use when the orchestrator's tasks must run **concurrently in separate worktrees**
rather than one cycle at a time. Crew mode is orchestrator mode plus isolation: the queue, budget, and
one-line-evidence rules in `references/orchestrator.md` are unchanged.

Do not stand up a coordination daemon for this. The harness already exposes the
primitives; `project.sh` already supplies the claim model. Map them directly:

| Need | Primitive |
| --- | --- |
| one worker per task, isolated | `Agent` with `isolation: "worktree"`, `run_in_background: true` |
| worker roster and live status | `ListAgents` — name, ref, busy/idle |
| relay a decision to a worker | `SendMessage` to the worker's name |
| hear that a worker finished | `SendMessage` `notify_when_idle: true` — one-shot, no polling |
| wake on state change, not on a timer | `Monitor` with an edge-triggered condition |
| overlapping edits across worktrees | `bin/crew-radar` (below) |
| durable claim, stale reap, resume | `project.sh claim` / `reap` / `context.sh --for=resume` |
| plan before building; race approaches | `Plan` agent type, or `$council` when the split is contested |

Two boundaries are not negotiable. **Never answer another session's permission
prompt or ask a peer to run what your own permissions refused** — that launders a
decision the human owns; route it back to the human instead. And **never edit a
worker's worktree yourself**: ask the worker by mail for a diff or a test result.

Ownership isn't visible in path or mtime: a worktree can sit idle for an hour and
still belong to a live peer, and a `.claude/worktrees/` path — the harness's own
convention, not the hand-made `<repo>-wt-<ticket>` layout — is a strong hint it
isn't yours. Match a worktree's basename against `ListAgents` before touching or
removing it; if it's someone else's, mail them to ask, don't `git worktree remove`
it. (Observed in practice 2026-08-28, across two sessions.)

Code-worktree isolation does **not** cover `WORKLOG_REPO`. Parallel crew workers
that `checkpoint.sh` / `archive.sh` the same clone are a write race: one
worker's pull can fail on an untracked path another worker just archived
(observed 2026-08-28, `people/oss/archive/review-pr-14851-b.md`). Serialize
mutating worklog helpers; keep parallelism in the code worktrees. Before each
mutation, `git -C "$WORKLOG_REPO" status --porcelain -- people/"$WORKLOG_LDAP"/`
must be empty or limited to the claimed `active/<slug>.md`. On pull failure,
return `blocked <slug> worklog pull failed` — do not return a SHA from the
code repo.

### Conflict radar

`crew-radar` takes the same `--roster` and annotates each owner with the agent
holding it (`feat-a@worker-7f`, or `@?` when nothing matches), so an overlap row
says who to mail rather than only which branch. Both tools accept a file, a
comma-separated list, or `-` for stdin. The column renders only on overlap rows,
so a clean repo shows nothing either way.

Two worktrees changing one file is a merge conflict surfacing early. Treat it as
evidence that **the split was wrong**, not that a worker misbehaved.

```bash
<skill-dir>/bin/crew-radar [--base <ref>] [--json] [--quiet] [--strict] <repo>
```

Exit `0` clean or info-only, `2` collision, `1` usage error. It runs no model and
costs no tokens, so it is safe to arm from `Monitor` or a `PostToolUse` hook.

`Monitor` turns each **stdout line** into an event; it has no exit-code
condition. So emit a line only when the verdict changes, and keep the radar's own
failures in the stream — a silent monitor is indistinguishable from a clean one:

`--json` answers in JSON on every path, failures included (`{"error": "..."}`),
so the fingerprint stays parseable even when the repo goes momentarily
unreadable. Exit `2` is a collision **verdict**, not a parse failure: fingerprint
stdout and do not bind `||` (or `set -o pipefail`) to radar's exit. A Monitor
that treats exit 2 as unparseable fires once on a real overlap and then looks
clean. Project it down to one line — the full payload as a fingerprint makes
every verdict change a large notification:

```bash
FP=$(mktemp); RADAR=<skill-dir>/bin/crew-radar
while true; do
  raw=$("$RADAR" --json <repo> 2>/dev/null) || true   # exit 2 is a verdict
  cur=$(printf '%s' "$raw" | jq -S -c '{warn,info,error,paths:[.overlaps[]?.path]}' 2>/dev/null) \
    || cur='{"error":"radar output unparseable"}'
  [ "$cur" = "$(cat "$FP")" ] || { printf 'crew-radar: %s\n' "$cur"; printf '%s' "$cur" >"$FP"; }
  sleep 30
done
```

Keep `error` in the projection. Dropping it makes a persistently failing radar
fingerprint-stable, so it emits once and then looks exactly like a clean repo.

Arm it once per parallel dispatch with `persistent: true`, and re-arm after any
resume: a monitor lost to a restarted session ends silently and nothing says so.

Act on severity:

- **`warn`** — an owner holds the path dirty, the branches are unrelated, or the
  pair is stacked and a later parent commit broke the ancestry chain. **Triage
  before re-dividing anything.** Only a child that *both* edits the file *and*
  targets the shared base can revert the parent's work; a child carrying stale
  copies it never edits is safe, and that `warn` is expected rather than a
  defect. Three cheap checks:

  1. `git log --oneline <merge-point>..<child> -- <file>` — 0 commits means the
     child never touched it.
  2. Check the MR/PR target branch: the parent, or the shared base?
  3. `git merge-tree --write-tree <parent> <child>` — simulate, then diff the
     resulting blob shas.

  Once triage clears the pair, decide who owns the file and mail both workers to
  divide it: one takes the file, the other takes an interface. If the overlap is
  structural, stop one worker and fold its task into the other, then say so to
  the human.
  **After a parent merges, re-run triage — the retarget is a two-part trap**
  (observed in practice 2026-08-28). The child's target flips to the shared base,
  which changes check 2 above; *and* it resets review state — the child MR came
  back `not_approved` and needed a fresh review. Merging the parent with
  `should_remove_source_branch: false` is the working mitigation: it keeps the
  child from pointing at a deleted branch during the window.

- **`info`** — every owner has the path committed and the branches form an
  ancestry chain. This is the expected footprint of deliberately stacking one
  branch on another. Leave it; mail the descendant once to keep the shared file
  read-only. Repeat `info` rows on those paths are noise.

### Reaping finished worktrees

`bin/crew-reap` is the radar's companion: the radar says who is still working,
this says who has finished. It costs no model call, so hand it to a cheap
utility agent rather than enumerating worktrees on frontier tokens.

```bash
ListAgents-names | <skill-dir>/bin/crew-reap [--target <ref>] [--apply] <repo>
```

**Dry run by default; `--apply` is required to remove anything.** It fetches the
target ref first and prints what it resolved to —
`target=origin/master@fed8242 (18:37, fetched)` — because the landed test is only
as fresh as that ref. A stale one fails safe but silently, reporting
"N commit(s) not in <target>", which reads as unlanded work when the ref simply
predates the merge. `--no-fetch` stays offline and says so in the header.

Two gates, both from real incidents:

- **Ownership.** Pass the live agent roster with `--roster <file|list|->`, or
  pipe it in on stdin. Measured on live data: the peer worktree this gate protected had
  **0 commits ahead of the target** — fully landed — so the landed gate alone
  would have deleted a running session's checkout. The two gates are not
  redundant. A worktree whose
  A worktree whose basename matches a live agent is never touched — merged is
  not the same as unowned, and mtime is not ownership. With no roster it removes
  nothing rather than guessing.
- **Landed.** A branch is deleted only when `git rev-list <target>..<branch>`
  is empty. Do **not** gate on an MR's merged flag: a squash sets it true while
  the branch's own commits are absent from the target. Removing a worktree is
  recoverable; deleting the branch is the irreversible half.

Exit `0` nothing to do, `3` something was reaped (or would be, in a dry run),
`1` usage error. Capture the output before piping it to `jq` — under
`set -o pipefail` the intentional exit 3 otherwise reads as failure.

Record the radar verdict as one typed line, like any other evidence:
`command: crew-radar <repo> — exit 0, 0 warn`.

Return to `SKILL.md` for budget, evidence, and terminal-state rules.
