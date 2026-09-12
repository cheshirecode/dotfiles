# Durable context and handoffs

Use before resume, delegation, compaction, or a cross-session checkpoint.
Distinguish local observations, commits, and pushed artifacts. A remote handoff
needs remotely reachable evidence: push authorized changes and verify the remote
ref before claiming delivery. A no-op review needs no artificial commit.
Temporary files may disappear or be inaccessible on another host; persist the
needed evidence through an authorized durable store before sending its pointer.
Do not use `.git/info/exclude` to hide run files; worktrees can share that file.

## Worklog

Use the installed Worklog owner for context, checkpoints and task lifecycle.
`WORKLOG_REPO` names the data clone, `WORKLOG_BIN` the skill's `bin/`, and
`WORKLOG_LDAP` the owning namespace. Verify the data remote and scope first.
`direnv exec` loads environment but does not change directory; set cwd explicitly
or use a subshell so a persistent shell cannot retarget the next code dispatch.

```bash
# Set these paths to the verified data clone and helper directory first.
(cd "$WORKLOG_REPO" && "$WORKLOG_BIN/context.sh" <slug> --for=resume)
(cd "$WORKLOG_REPO" && "$WORKLOG_BIN/context.sh" <slug> --for=compact)
```

A valid explicit environment works without direnv. Only if Worklog itself is
unavailable, use the host tracker and one authorized durable artifact; label
`worklog-checkpoint: unavailable — <fallback reference>`. Hydrate the tracker
according to the Worklog owner's dedupe rules. Shared writes belong to the parent.

## Compact pack

- `objective`: stable task identity and accepted outcome.
- `known evidence`: repository, revision, checks/results and artifact references.
  Uncommitted review names HEAD and a scoped diff fingerprint including relevant
  untracked files. Do not label an uncommitted artifact as pushed.
- `constraints`: ownership, allowed writes, shared surfaces, acceptance checks
  and user corrections or exclusions.
- `budget`: remaining declared work; role changes do not reset it.
- `requested return`: evidence, uncertainty, next action, and intended owner.

Recovery handles include state path, state fingerprint, terminal status, next
action, typed evidence reference, and approval boundary. Send this pack instead
of replaying the parent transcript. API conversation history is separate: leave
history management to the host; a handoff summary does not authorize rewriting it.

## Accept a return or restart

Recheck task/repository identity and revision or diff fingerprint. Changed head,
base or scoped diff invalidates affected verification. Reconcile duplicates with
the task history before advancing; count accepted work once. A retained worker
name does not prove retained context: re-brief from the pack after a reset.
Validate saved state and replay the recovery check before trusting intervention.
Keep terminal predecessors immutable; follow [protocol.md](protocol.md) for resume.
