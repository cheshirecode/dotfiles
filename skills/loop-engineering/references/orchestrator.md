# Orchestrator mode

Use for a program with three or more Worklog tasks. The parent selects work,
verifies returns, owns shared persistence and records one driver call per cycle.
Read [crew.md](crew.md) for delegation, and [models.md](models.md) when Sol, Astra
or Fable leads. Model selection does not change the parent responsibilities.

## Scope and budget

Reuse a matching project; create one only when the goal needs it. Declare which
children belong to this run. A scoped wave inside a broader project can finish
without archiving unrelated work. Define delivery separately from merge/deploy.

Honor the user's unit, ceiling and minimum. Otherwise use the driver default of
20 turns and choose a larger explicit ceiling at initialization only if the task
graph needs it. Never replace an explicit budget with 999 or extend it silently.
Batch independent reads; keep dependencies and shared mutations sequential.

Validate uncertain decomposition with [interrogate.md](interrogate.md). Only
costly or unclear children need a separate plan review; well-scoped work proceeds.
Material disagreements follow [protocol.md#escalation](protocol.md#escalation).

## Project and cycle

Resolve the Worklog environment through [durable-context.md](durable-context.md).
New project JSON contains `{slug, kind, depends_on}`; use supported Worklog kinds
such as `impl`, `review`, `design`, `cleanup`, not an invented `docs` kind.

```bash
# For a new project; use the owner's creation procedure first.
"$WORKLOG_BIN/project.sh" new <project> --goal "<goal>" --objective "<outcome>" \
  --repos <owner/repo> --tasks-json '<task-array>'
# For another task in an existing project:
"$WORKLOG_BIN/project.sh" add-child <project> <child> --kind=review
# Each cycle:
"$WORKLOG_BIN/project.sh" next <project> --json
"$WORKLOG_BIN/project.sh" claim <child>
"$WORKLOG_BIN/context.sh" <child> --for=compact
```

Claim before dispatch; the driver queue probe does not claim or start a worker.
Use the compact pack and explicit acceptance checks. Dispatch through an authorized
capability, or execute in-band. Wait only for dependencies. Read-only workers return
evidence; even isolated code writers leave shared Worklog updates to the parent.

Before accepting results, verify task/repository identity, revision and checks.
A head/base/diff change invalidates affected review evidence. Reconcile duplicate
returns before advancing. Re-run an affected check before relaying domain claims
into another task or PR; otherwise mark the claim unverified.

Checkpoint status and detailed evidence through Worklog. Archive only when the
child's accepted outcome is complete; PR delivery may remain in-review until merge.
Release claims when handing off unfinished work. Verify the Worklog commit and
successful push before recording delivery. Use `add-child` for re-review work so
parent membership stays valid; verify the graph before claiming it.

```bash
python3 <skill-dir>/scripts/loop_run.py <run-dir> \
  --evidence "git: <worklog-sha> — <child>: <verified status>" \
  --next-action "<next authorized task or check>"
```

Keep findings in the task and one index line in state. A stale-SHA archive is
historical evidence, not current-head completion. A watcher is optional; without
one, recheck heads after returns and before persistence.

## Completion

`project.sh next <project> --json` uses `worklog-project-next/v1`. Exit 0 means
eligible; exit 1 may mean empty, blocked, missing or error. Bootstrap failures may
return no JSON. Parse status and identity; exit 1 alone never proves completion.

For a whole-project goal, require status empty, task null, matching schema/project,
`project.sh verify` success, and goal evidence. Then checkpoint and archive the
parent through Worklog and verify its push. A failed helper stops that progression.
For a scoped wave, verify its declared children/outcomes and the project graph;
leave unrelated children and the parent active. Queue emptiness is not a substitute
for the user's acceptance criteria, nor a prerequisite for a partial-project wave.

Run the evidence gate after recording required Git, artifact and delivery checks.
Only its satisfied verification permits `loop_run.py --stop complete`. Blocked
work retains a concrete replay action under the protocol's resumable outcome.
The driver owns budget exhaustion; do not calculate a second budget here.
