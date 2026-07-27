# Loop protocol

Read only when the root router needs exact transition, effect, worklog, or
handoff rules.

## State CLI

Use `scripts/loop_state.py`; do not reimplement its state machine or hand-edit
the JSON.

- `init` creates a `running` state and refuses overwrite unless `--force`.
- `advance` records a failed or nonterminal cycle, consumes one budget unit by
  default, and atomically changes the state to `budget_exhausted` at the
  ceiling. Use `--consume N` only when one recorded cycle represents `N`
  declared units; it cannot exceed the remaining budget.
- `finish` records exactly one terminal outcome. `complete` requires
  `--verification` naming tool output or an artifact.
- `annotate` appends corrected evidence without reopening terminal state or
  changing the consumed budget.
- `validate` checks the schema and transition invariants.
- `show` prints the five-field contract; `--json` returns the full history.

Every write is atomic. A failed transition leaves the previous state unchanged.

## Effect boundary

- Declare allowed effects and the approval boundary at initialization when
  files, external systems, or user data may change.
- Parallelize independent read-only observations.
- Serialize writes unless the runtime proves isolation.
- After a contradiction, stop affected mutations, revise the hypothesis, and
  replay the original discriminating check.

The script records state; it never grants permission, executes the action,
verifies external truth, delegates, or schedules a wakeup.

## Worklog composition

For work spanning sessions, compaction, retries, or agents:

1. Existing task: invoke installed `worklog` in `context` mode with
   `<slug> --for=resume`; immediately hydrate the host tracker from the
   tracker-ready snippet.
2. New durable task: invoke `plan`, then slugless `sync`; let sync survey,
   report, and wait for confirmation before creation.
3. Cold delegation: invoke `context` with `<slug> --for=compact`, follow tracker
   dedupe, and pass the returned pack directly to the delegate.
4. Boundary or terminal state: persist arbitrary evidence or task-body changes
   through worklog, invoke `sync` or its supported checkpoint helper, then
   rehydrate the tracker.

If worklog is unavailable, use the host tracker plus one authorized durable
project file. Label that fallback and do not claim a worklog checkpoint.

## Delegation

- Delegate a bounded lookup, research, or verification question.
- Include the objective, evidence, constraints, budget, and requested return.
- Require evidence, uncertainty, and one proposed next action.
- Reconcile returns into the parent state before any write.

## Terminal outcomes

- `complete`: external evidence proves the goal.
- `blocked`: an external dependency prevents safe progress.
- `needs_human`: ambiguity, authority, or risk requires a decision.
- `budget_exhausted`: the declared ceiling was consumed.
- `cancelled`: the user or host stopped the run.
- `continue_scheduled`: this bounded run ended and a real scheduler owns the
  next wakeup.
