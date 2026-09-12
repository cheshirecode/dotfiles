## Preserve durable context

**Uncommitted working-tree state is not durable state.** A checkpoint records
an artifact's location; it does not preserve its bytes. Within the authorized
scope, commit and push artifacts claimed as remotely recoverable, then verify
the exact ref with `git ls-remote`. Label local-only or uncommitted work as such;
a checkpoint does not authorize publishing it.

Invoke installed `$worklog` for resume context and checkpoints at compaction,
delegation, retry exhaustion, scheduled handoff, or termination. Its
`references/preamble.md` owns environment loading and `modes/context.md` owns
host-specific tracker selection. Verify the target clone and identity:
`direnv exec` loads environment but does **not** change directory. Without a
clone `.envrc`, set `WORKLOG_REPO=<clone-dir>` explicitly and run from that clone.
For resume, use `context.sh <slug> --for=resume --tracker=<active-host>`.

Before cold delegation, pass `context <slug> --for=compact` directly; `spawn`
does not enrich it. If Worklog is unavailable, use the state path plus one
authorized artifact and label `worklog-checkpoint: unavailable — local fallback`.

Pack only objective, known evidence, constraints, budget, requested return,
and recovery handles. Keep raw output in system temp or CCR, not the parent
transcript; never rebuild a handoff by replaying it. For brittle classification or handoff sequencing, read
[examples.md](examples.md); otherwise stay zero-shot.
