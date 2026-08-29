# Contrastive loop fixtures

Read only when state classification, effect ordering, or handoff routing is
ambiguous.

## 0. Basic single-task loop

INPUT

> Verify that the API endpoint returns 200 for valid requests. Budget: 5 checks.

OUTPUT

Initialize the loop:

```bash
python3 <skill-dir>/scripts/loop_state.py init \
  --state /tmp/api-check.json \
  --goal "API endpoint returns 200 for valid requests" \
  --evidence "endpoint URL confirmed" \
  --budget-unit checks \
  --budget-limit 5 \
  --next-action "send test request with valid payload"
```

Run one cycle:

```bash
# After executing the check and capturing output
python3 <skill-dir>/scripts/loop_state.py advance \
  --state /tmp/api-check.json \
  --evidence "command: curl -s -o /dev/null -w '%{http_code}' — 200" \
  --next-action "verify response body schema"
```

On success after verification:

```bash
python3 <skill-dir>/scripts/loop_state.py finish \
  --state /tmp/api-check.json \
  --status complete \
  --verification "curl exit 0 and HTTP 200 confirmed" \
  --evidence "command: curl response — 200 OK with valid schema"
```

This pattern scales to multi-hypothesis diagnosis (fixture 1), delegation
(fixture 2), and orchestrator programs (fixture 4).

## 1. Interactive diagnosis

INPUT

> Find and fix a flaky unit test. Stop after three unsuccessful hypotheses.

OUTPUT

```text
goal: targeted test passes three consecutive runs
progress_evidence: failure reproduced once; no source mutation yet
budget: 0/3 hypotheses
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
[cycle 1: claim lint-all-skills → context --for=compact → delegate → return archived lint-all-skills <sha> → advance]
[         advance evidence: "lint-all-skills: archived"]
[cycle 2: claim fix-sh-preamble → in-band → archive → advance]
[         advance evidence: "fix-sh-preamble: archived"]
[cycle 3: claim fix-py-errors → delegate → archive → advance]
[         advance evidence: "fix-py-errors: archived"]
[project next reports "all tasks ... are archived (nothing left)" + project verify exits 0 → finish complete]
```

Same prompt in natural language:

> Use loop-engineering orchestrator mode. Goal: audit skills for shellcheck
> regressions.

Mid-run escalation is resumable, not terminal:

```text
[cycle 2: independent returns disagree → council foreground → verified verdict]
[         replay check passes → archive fix-py-errors → advance once]
```

No manual JSON creation. No separate setup turn. Loop state is ~1KB even at
100+ cycles because evidence is one line per task — all detail lives in
worklog commits.

Delegate return contract: `archived <slug> <sha>` is the success case;
`blocked <slug> <reason>` preserves a non-success outcome without returning a
full task narrative.

## 5. Discovery keyed on a join dimension

INPUT

> Watch for MRs in my team's repos that need review.

OUTPUT (agent runs the inverse sweep, not just the forward one)

```text
[sweep A: MRs whose title/branch carries a ticket id -> 6 found]
[sweep B: tickets on the team field -> resolve to MRs -> 5 found]
[reconcile: A\B = 1 MR whose ticket is untagged; B\A = 1 MR in a repo not enumerated]
[evidence: "command: two sweeps reconciled — 2 items visible to exactly one"]
```

If a loop discovers work through a join key, items lacking that key are
invisible **by construction**, not by accident: a title-keyed sweep cannot see an
untagged MR, and a ticket-keyed sweep cannot see a repo it does not enumerate.
Run the inverse sweep and reconcile the two sets. Observed 2026-08-28: each
direction missed something real on the same day.

## 6. Reading a tool whose exit code is a verdict

INPUT

> Fingerprint crew-radar for a Monitor, and check it after the fix.

OUTPUT (capture, then parse — never pipe a verdict into a parser)

```bash
RADAR=<skill-dir>/bin/crew-radar   # not on PATH; always resolve via <skill-dir>

# WRONG — pipefail binds the pipeline to the radar's exit 2, and a real
# collision is reported as unparseable output. (Subshell keeps the option
# from leaking into the RIGHT form below.)
(
  set -o pipefail
  cur=$("$RADAR" --json "$REPO" | jq -S -c '{warn,info}') || cur='{"error":"unparseable"}'
)

# RIGHT — capture first; only a jq failure reaches the sentinel.
raw=$("$RADAR" --json "$REPO" 2>/dev/null) || true
cur=$(printf '%s' "$raw" | jq -S -c '{warn,info,error}' 2>/dev/null) \
  || cur='{"error":"unparseable"}'
```

A non-zero exit that *is* the answer — `crew-radar` 2 for a collision,
`crew-reap` 3 for a removal, a linter's 1 for findings — inverts the usual
reading. Under `set -o pipefail`, or `... | tail -1; echo $?`, the shell reports
the pipeline rather than the command, so a correct tool reads as broken and a
clean run reads as a failure.

Six occurrences in one day across three agents, including one while verifying
the fix for it and one in a test written by the person who had documented the
trap that morning. **The knowledge does not fire at the moment you type the
pipeline**, so a caution does not prevent it — the executable fixtures in
`tests/test_crew_radar.sh` and `tests/test_crew_reap.sh` do, because they
assert both that the correct form works and that the wrong form still fails.
Copy those when adding a tool whose exit code carries meaning.
