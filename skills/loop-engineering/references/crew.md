# Crew mode — parallel worker sessions

Use when the orchestrator needs concurrent observations or independently
isolated workers rather than one cycle at a time. Crew mode keeps the queue,
budget, and one-line-evidence rules in `references/orchestrator.md`.

Do not assume that delegation isolates files. First inspect the current
harness's actual tool schema. If it cannot create a private worktree or sandbox
for each worker, parallel delegates are **read-only** and the orchestrator is
the single writer. A clean radar result does not prove isolation.

Map available primitives by capability, not by a different host's tool names:

| Need | Portable requirement | Codex collaboration harness | OpenCode (`task` tool) |
| --- | --- | --- | --- |
| start a worker | dispatch is authorized; writes require proven isolation | `spawn_agent`; no isolation flag, shared filesystem, so read-only only | `task` with chosen `subagent_type`; read-only unless proven isolated worktree |
| roster and status | list active workers before ownership decisions | `list_agents` | none — orchestrator tracks via state file + worklog claims |
| relay or resume work | address one worker explicitly | `send_message`; replies arrive via the `wait_agent` mailbox, not a dedicated reply primitive | use `task` with explicit description referencing child slug |
| wait for completion | use an event/mailbox wait when available | `wait_agent`; there is no `Monitor` primitive | in-band: begin next cycle immediately while state is `running` |
| stop a worker | interrupt only the named worker | `interrupt_agent` | orchestrator stops dispatching that worker; state remains bound |
| overlapping worktree edits | run deterministic conflict evidence | `bin/crew-radar` (below) | `bin/crew-radar` (below) — same repo, same radar |
| durable claim, stale reap, resume | use the Worklog claim lifecycle | `project.sh claim` / `reap` / `context.sh --for=resume` | `$WORKLOG_BIN/project.sh` / `context.sh` — host-agnostic paths |

### Shared-filesystem boundary

Codex subagents share the same filesystem and current directory. Concurrent
Codex delegates may inspect files, git history, logs, and tool output, but must
not edit files, create patches or artifacts, change the index, commit, run
mutating Worklog helpers, or use the filesystem as a message bus. They return
evidence and proposed changes through the collaboration tools. The orchestrator
applies at most one write set at a time, verifies it, runs the radar, and only
then starts the next write. Manually naming different directories does not
upgrade this harness into proven isolation. This applies on every host: Codex
subagents, OpenCode task dispatch, Cursor subagents — none provide filesystem
isolation by default.

Two boundaries are not negotiable. **Never answer another session's permission
prompt or ask a peer to run what your own permissions refused** — that launders a
decision the human owns; route it back to the human instead. And **never edit a
worker's worktree yourself**: ask the worker by mail for a diff or a test result.

Ownership isn't visible in path or mtime: a worktree can sit idle for an hour and
still belong to a live peer. Match worktrees against the current worker roster
before touching or removing one; if it belongs to another worker, message that
worker instead of running `git worktree remove`. (Observed in practice
2026-08-28, across two sessions.)

Even proven code-worktree isolation does **not** cover `WORKLOG_REPO`. Parallel
crew workers that `checkpoint.sh` / `archive.sh` the same clone are a write race: one
worker's pull can fail on an untracked path another worker just archived
(observed 2026-08-28, `people/oss/archive/review-pr-14851-b.md`). Serialize
mutating Worklog helpers. Permit concurrent code writes only on a harness that
actually proved separate worktrees; Codex remains read-only in parallel. Before
each mutation, `git -C "$WORKLOG_REPO" status --porcelain --
people/"$WORKLOG_LDAP"/` must be empty or limited to the claimed
`active/<slug>.md`. On pull failure, return `blocked <slug> worklog pull failed`
— do not return a SHA from the code repo.

### Conflict radar

`crew-radar` takes `--roster` (a file, a comma-separated list, or `-` for
stdin; `crew-reap` below accepts the same form) and annotates each owner with
the agent holding it (`feat-a@worker-7f`, or `@?` when nothing matches), so an
overlap row says who to mail rather than only which branch. The column renders
only on overlap rows, so a clean repo shows nothing either way.

Two worktrees changing one file is a merge conflict surfacing early. Treat it as
evidence that **the split was wrong**, not that a worker misbehaved.

```bash
<skill-dir>/bin/crew-radar [--base <ref>] [--roster <file|list|->] [--json] [--quiet] [--strict] <repo>
```

Exit `0` clean or info-only, `2` collision, `1` usage or repo error. It runs no model and
costs no tokens. Run it before a parallel wave, after workers return, and before
and after each serialized write. Record every boundary verdict; do not claim
that an absent continuous monitor means the interval was observed.

Exit `2` is a collision **verdict**, not a parse failure. Capture stdout and the
exit code separately, then project the JSON to one evidence line:

```bash
RADAR=<skill-dir>/bin/crew-radar
if raw=$("$RADAR" --json <repo> 2>/dev/null); then radar_rc=0; else radar_rc=$?; fi
cur=$(printf '%s' "$raw" | jq -S -c '{warn,info,error,paths:[.overlaps[]?.path]}') \
  || cur='{"error":"radar output unparseable"}'
printf 'command: crew-radar <repo> — exit %s, %s\n' "$radar_rc" "$cur"
```

`--json` answers in JSON on every path, failures included (`{"error": "..."}`).
Keep `error` in the projection. If the host does expose a persistent watcher,
it may fingerprint verdict changes, but crew correctness cannot require that
optional primitive. In Codex, use `wait_agent` for worker mailbox changes and
rerun the radar synchronously at the boundaries above; do not start a polling
daemon or pretend `wait_agent` watches files.

One-shot Codex example: spawn two read-only audit agents, wait for both with
`wait_agent`, collect their evidence, run `crew-radar`, apply one reconciled
patch in the root session, verify it, then run `crew-radar` again. Do not assign
the agents different files and let them write concurrently.

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
ListAgents-names | <skill-dir>/bin/crew-reap [--target <ref>] [--roster <file|list|->] [--apply] [--no-fetch] [--json] <repo>
```

**Dry run by default; `--apply` is required to remove anything.** It fetches the
target ref first and prints what it resolved to —
`target=origin/master@fed8242 (18:37, fetched)` — because the landed test is only
as fresh as that ref. A stale one fails safe but silently, reporting
"N commit(s) not in <target>", which reads as unlanded work when the ref simply
predates the merge. `--no-fetch` stays offline and says so in the header.

Exit `4` means `--apply` was refused because the ownership gate was inert.

Two gates, both from real incidents:

- **Ownership.** Pass the live agent roster with `--roster <file|list|->`
  (a bare single name is rejected — it is indistinguishable from a typo'd
  filename, and reap deletes; for one name append a comma: `--roster 'a-1,'`), or
  pipe it in on stdin. Measured on live data: the peer worktree this gate protected had
  **0 commits ahead of the target** — fully landed — so the landed gate alone
  would have deleted a running session's checkout. The two gates are not
  redundant. A worktree whose basename matches a live agent is never touched — merged is
  not the same as unowned, and mtime is not ownership. With no roster it removes
  nothing rather than guessing.
- **Landed.** A branch is deleted only when `git rev-list <target>..<branch>`
  is empty. Do **not** gate on an MR's merged flag: a squash sets it true while
  the branch's own commits are absent from the target. Removing a worktree is
  recoverable; deleting the branch is the irreversible half.

Exit `0` nothing to do, `3` something was reaped (or would be, in a dry run),
`1` usage or repo error. Capture the output before piping it to `jq` — under
`set -o pipefail` the intentional exit 3 otherwise reads as failure. The exit
code is not the whole verdict: a `keep … removal failed` row does not raise the exit code
and a `reap … branch delete failed` row still exits `3` — grep the rows (or
`--json` `.rows[].reason`) before treating either as clean.

Record the reap verdict as one typed line, like any other evidence:
`command: crew-reap <repo> — exit 3, 2 worktree(s) reaped`.

Return to `SKILL.md` for budget, evidence, and terminal-state rules.
