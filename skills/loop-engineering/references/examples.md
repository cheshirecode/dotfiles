# Contrastive loop fixtures

Read only when state classification, effect ordering, or handoff routing is
ambiguous.

## 1. Interactive diagnosis

INPUT

> Find and fix a flaky unit test. Stop after three unsuccessful hypotheses.

OUTPUT

```text
goal: targeted test passes three consecutive runs
progress_evidence: failure reproduced once; no source mutation yet
budget: 3 hypotheses
next_action: isolate timing-dependent assertions
terminal_status: running
```

Run one discriminating check per hypothesis. Serialize edits and test after each
one. Continue immediately between hypotheses while state is `running`; do not
return an intermediate handoff. End `complete` only with three passing runs;
otherwise end `budget_exhausted` with failures and the safest next action.
When the terminal run itself consumes a declared unit, use `finish --consume 1`;
never also `advance` for that same unit.

For `blocked`, `needs_human`, `budget_exhausted`, or `continue_scheduled`, pass
the exact replay or intervention check through `finish --next-action`. For
`complete` or `cancelled`, omit that flag; the script clears the prior running
action so the terminal state cannot advertise obsolete work.

If a fresh check later contradicts evidence in a saved terminal run, append the
correction and revalidate the state:

```bash
python3 <skill-dir>/scripts/loop_state.py fingerprint \
  --state <state-file>
# Pass the exact printed value from the expected snapshot.
python3 <skill-dir>/scripts/loop_state.py annotate \
  --state <state-file> \
  --expect-sha256 <printed-sha256> \
  --evidence "Correction: isolated rerun reproduced the timing failure"
python3 <skill-dir>/scripts/loop_state.py validate --state <state-file>
python3 <skill-dir>/scripts/loop_state.py show --state <state-file>
```

Confirm the terminal status and consumed budget remain unchanged. The earlier
evidence remains in history. Start a new authorized state file for further work;
do not reopen the terminal run.

## 2. Worklog-backed delegation

INPUT

> Resume `auth-flake`, delegate context lookup, then decide the next fix.

OUTPUT

Invoke the installed `worklog` skill in `context` mode with
`auth-flake --for=resume`, then immediately hydrate the host tracker from its
tracker-ready snippet. Before delegation, invoke `context` mode with
`auth-flake --for=compact` and give that returned pack directly to each
independent read-only delegate. Follow worklog's dedupe rule so compact lookup
does not recreate tracker items already hydrated by resume. Ask one delegate
for failure-history evidence and another for current call-site evidence.
Reconcile both returns before editing. Persist new task evidence through the
worklog protocol, invoke `sync` mode for `auth-flake`, and rehydrate the tracker.

Do not pass the full parent transcript or let delegates write concurrently.

## 3. Scheduled monitor without a portable scheduler

INPUT

> Check CI every 15 minutes until it passes.

OUTPUT

Read `references/hosts.md`. If the active host exposes an authorized recurrence
primitive, schedule bounded checks and end each run `continue_scheduled` until
CI evidence satisfies the goal. If no such primitive is available, end
`needs_human` and name the missing capability.

At each verified wakeup, use `resume` to create a successor bound to the prior
`continue_scheduled` state, replay the CI check, and keep cycling. If a
credential or authority blocker requires intervention, checkpoint, ask for that
specific intervention, then resume a successor and replay the blocked check.

Do not claim that a timer or stop hook exists merely because another host
supports one.

## 4. Multi-task orchestrator program

INPUT

> Audit all skills for shellcheck regressions.

OUTPUT (agent decomposes, creates project, cycles through tasks)

```text
[sequential-thinking: 3 tasks identified — lint-all-skills, fix-sh-preamble, fix-py-errors]
[budget: 999 (safety net; real limit is queue emptiness)]
[project new: shellcheck-audit with 3 children]
[cycle 1: claim lint-all-skills → context --for=compact → delegate → archive → advance]
[         advance evidence: "lint-all-skills: archived"]
[cycle 2: claim fix-sh-preamble → in-band → archive → advance]
[         advance evidence: "fix-sh-preamble: archived"]
[cycle 3: claim fix-py-errors → delegate → archive → advance]
[         advance evidence: "fix-py-errors: archived"]
[project next exits 1 → finish complete with verification]
```

No manual JSON creation. No separate setup turn. Loop state is ~1KB even at
100+ cycles because evidence is one line per task — all detail lives in
worklog commits.

Same prompt in natural language:

> Use loop-engineering orchestrator mode. Goal: audit skills for shellcheck
> regressions.

```text
shot_count: few
format: INPUT/OUTPUT
examples_or_skip_reason: three distinct fixtures cover diagnosis, delegated durable context, and scheduled handoff
risk_check: keep fixtures about classification and sequencing so agents do not copy task-specific details
acceptance_test: an unseen resumable task hydrates context, bounds the run, and ends with evidence plus one valid terminal status
```
