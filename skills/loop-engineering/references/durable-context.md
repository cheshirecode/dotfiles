## Preserve durable context

**Uncommitted working-tree state is not durable state.** A checkpoint records
that work exists; it does not make it exist. Commit and push before any
checkpoint claiming an artifact, and confirm with `git ls-remote` — local
`git log` only proves the commit reached this machine, and a forge API can serve
a stale head SHA. Observed 2026-08-28: worktree fixes checkpointed, instance
died, record survived, work did not.

When the installed `worklog` protocol is available, hydrate resume context
before initialization and checkpoint verified state at compaction, delegation,
retry exhaustion, scheduled handoff, or termination. Resolve `$WORKLOG_BIN` to
the worklog skill's `bin/` directory (`~/.claude/skills/worklog/bin`, `~/.agents/skills/worklog/bin`, or the repo's `skills/worklog/bin`). For an existing task, run
`direnv exec <clone-dir> "$WORKLOG_BIN"/context.sh <slug> --for=resume`, where `<clone-dir>` is the target repo clone whose `.envrc` sets `WORKLOG_REPO`. `direnv exec` loads that env but does **not** change directory (measured), so with no `.envrc` it adds nothing and the slug resolves against your *current* repo — the wrong vault, silently. If `direnv` or the `.envrc` is missing, pass the target explicitly: `WORKLOG_REPO=<clone-dir> "$WORKLOG_BIN"/context.sh <slug> --for=resume`, and label the run `worklog-checkpoint: unavailable — local fallback`.
Before cold delegation, pass the returned
`context <slug> --for=compact` pack directly; do not pass the parent transcript
or imply that `spawn` enriches the pack. If Worklog or its environment is not
available, use the explicit state path plus one authorized artifact and label
the run `worklog-checkpoint: unavailable — local fallback`.

Pack before compaction: pass only the objective, known evidence, constraints,
budget, requested return, and recovery handles. Keep raw output in system temp
or CCR; never rebuild a handoff by replaying the parent transcript.

For brittle state classification or handoff sequencing, read
[references/examples.md](examples.md). Otherwise stay zero-shot.

## Accept a handoff

Use the existing compact pack; do not introduce another queue or schema:

- `objective`: stable task identity and the accepted outcome.
- `known evidence`: observed repository, revision, check commands/results, and
  artifact references. A committed transfer names its exact SHA. A read-only
  review can name HEAD plus a fingerprint of the scoped diff, including relevant
  untracked files; it does not require making a commit.
- `constraints`: assigned owner, allowed writes, shared surfaces, and acceptance
  checks. Code isolation does not grant shared Worklog ownership.
- `budget`: the remaining bounded work; a role change does not reset it.
- `requested return`: the crew return contract and intended next owner.

Recovery handles point to the existing task/state/artifact. Local observation,
committed work, and remote delivery are different evidence claims.

Before accepting a return, recheck task/repository identity and the reviewed
revision or diff fingerprint. A changed head, base, or scoped diff invalidates
its affected review evidence; replay those checks. Reconcile duplicate returns
against the existing task/state history before advancing; never count the same
accepted work twice. A no-op review still needs evidence of the accepted checks,
but it needs no artificial commit or forced downstream handoff.

On restart, read the existing claim and state before accepting more work. Keep
terminal predecessors immutable; use the protocol's bound successor when a
resumable condition clears. A handoff or all-role broadcast never substitutes
for the completion evidence gate.
