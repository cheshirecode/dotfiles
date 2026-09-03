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
- `resume --state <terminal> --new-state <successor>` starts a fresh running
  state after `blocked`, `needs_human`, `budget_exhausted`, or
  `continue_scheduled`. It inherits the goal and cumulative budget, requires
  intervention evidence (`--evidence`) and a next action, and binds the
  successor to the predecessor path, status, and
  SHA-256. `--new-state` must be a distinct, nonexistent path. Use
  `--extend-budget N` only with explicit authorization; exhausted predecessors
  require an extension. It rejects `running`, `complete`, and `cancelled`.
- `finish` records exactly one terminal outcome. `complete` requires
  `--verification` naming tool output or an artifact. It leaves budget
  unchanged by default; use `--consume N` when the terminal cycle spent `N`
  declared units. Resumable outcomes require `--next-action`; `complete` and
  `cancelled` reject that flag and clear the prior running action. Every
  executed cycle must be accounted exactly once by `advance` or `finish`.
- `fingerprint` validates a state and prints the SHA-256 of its exact bytes.
- `annotate --expect-sha256 <fingerprint>` appends corrected evidence without
  reopening terminal state or changing the consumed budget. Capture the
  fingerprint after the last successful transition. A mismatch rejects the
  write; verify state ownership instead of refreshing an unexpected mismatch.
  Annotation cannot add a next action to `complete` or `cancelled`.
- `validate` checks the schema and transition invariants.
- `show` prints the five-field contract; `--json` returns the full history.
- `--quiet` (accepted by every subcommand; `fingerprint` accepts it but ignores
  it and always prints the digest) replaces the state document with
  one index line: `<status> <used>/<limit> <unit> — next: <action>` while
  `running`; a terminal line shows the verification instead of the next action
  (`<status> <used>/<limit> <unit>[ — <verification>]`), so read a resumable
  state's required next action from the state file, not the quiet line.

Every write is atomic. Mutating commands also hold an adjacent process lock
across the full read-modify-write transition, so concurrent CLI processes apply
their transitions serially. A failed transition leaves the previous state
unchanged. Malformed CLI usage exits `2` with a `usage:` error. A well-formed
command rejected by the state contract exits `3` with a `loop-state:` error.

## Continuous execution and intervention

- While state is `running`, execute the next authorized cycle immediately. Do
  not stop at an intermediate progress update or ask for permission already
  granted by the effect boundary.
- On `blocked` or `needs_human`, checkpoint durable context and ask for the
  smallest specific intervention. Include the predecessor state path and the
  exact check that will prove the blocker cleared.
- After intervention, create a successor with `resume`, record the intervention
  as supplied but pending verification, replay that check, append verified
  clearing evidence, and keep iterating while the successor remains `running`.
- On `continue_scheduled`, a verified scheduler wakes the agent; the agent
  creates the successor and replays the stopping check. Active-turn
  continuation and background recurrence are distinct.
- A user may authorize a successor after `budget_exhausted`; do not silently
  grant more budget. Never resume `complete` or `cancelled`.

## Cycle decision record

Before an action that can change the hypothesis, write a compact three-part
record in the cycle evidence or durable task file:

```
`hypothesis`: <the smallest claim this action tests>
`falsifier`: <the observable result that would reject the claim>
`replay`: <the exact check that must pass after a fix or intervention>
```

Keep to one line in loop state (`hypothesis=X falsifier=Y replay=Z`); retain
expanded reasoning only in a durable artifact (worklog task file, /tmp log).
Use `=` separators and no spaces around them in the compact form; use colons
in expanded form above. If the result is neither a confirmation nor a falsifier,
advance with a narrower next action rather than claiming progress.

Preserve verifier exit status when output is piped or truncated:
capture the producer status first, or write the full output to an artifact
before summarizing it; a successful `tail`, formatter, or parser is
not evidence that the producer passed. Use `set -o pipefail` only when a
nonzero producer exit means failure — for a verdict-carrying exit code (`crew-radar` 2, `crew-reap`
3, a linter's findings) pipefail inverts the reading; see examples.md §6.

Evidence lines use the same compact shape: `kind: reference — result`. The
allowed kinds are `command`, `artifact`, `git`, `github`, and `url`; a missing
or untyped reference is an indexability failure, not completion evidence.

## Effect boundary

- Declare allowed effects and the approval boundary at initialization when
  files, external systems, or user data may change.
- Parallelize independent read-only observations.
- Serialize writes unless the runtime proves isolation.
- After a contradiction, stop affected mutations, revise the hypothesis, and
  replay the original discriminating check.

Before every mutation, run this effect preflight:

1. What exact path, provider, or person can this action affect?
2. Is that target listed in `allowed_effects`?
3. Does the action cross `approval_boundary` or require a new authority?
4. What read-only check will prove that the intended target, and no adjacent
   target, changed?
5. Is the action reversible? Name the irreversible ones in
   `approval_boundary` — merge, deploy, publish, a secret write, a ticket
   transition — and re-read that list here. Questions 1-4 treat every write
   alike, so an authority to comment reads as an authority to merge unless the
   boundary says otherwise.
6. Does the action *satisfy someone else's armed automation*? An approval that
   releases an armed `merge_when_pipeline_succeeds` merges the MR; you did not
   call merge, you supplied its last condition. Check the flag before any action
   whose completion you would not be permitted to perform directly.
7. Has another session declared a constraint on this artifact? Authority
   settles whether you *may* act; it does not tell you whether you *should*.
   Read the owning task's notes before an irreversible action, even when every
   mechanical signal is green. Verified 2026-08-28: an MR was approved,
   mergeable, threads resolved and authored by the acting identity — and
   merging it alone would have moved production onto a broken auth pairing,
   because the code change had to land in the same deploy as a secret rotation.
   No API field carried that; it existed only in a peer's worklog task.

If any answer is unknown, stop before the write and narrow the action or end
`needs_human` with the missing authority named.

The script records state; it never grants permission, executes the action,
verifies external truth, delegates, or schedules a wakeup.

## Verifying a claim

Most wrong answers this skill has produced were not reasoning errors. They came
from an instrument that answered a question **adjacent** to the one asked, and
whose output is indistinguishable from the right answer. `$PPID` is "my parent",
not "my session". "Newest file" is not "mine". A clean grep for the wrong string
looks exactly like a real negative. A pipeline's exit status is not its
producer's. `git stash` before re-running a suite removes the new fixtures along
with the fix, so the green means they never ran.

Four rules, in order of how often they would have caught it:

1. **Name the instrument's question, then compare it to yours.** Before stating
   "X is/isn't in Y", re-run the check with X literally in it, in the same turn
   as the claim. A negative inherited from an earlier command answered that
   command's question. Two more of the same shape, both live: `git diff
   --name-only HEAD..origin/main` reports the *union* of both sides' changes,
   not the overlap — it named nine colliding files where the merge base showed
   two. And one repo carried two author identities differing by a single
   capital letter and an email domain, so `git log --author` on either silently
   answered about the other half of the history.
2. **Build the check so the wrong strategy visibly fails.** A fixture where
   "newest" and "mine" happen to coincide certifies the bug. Make them disagree.
   Prove a new fixture by reverting the *implementation* and leaving the fixture
   in place — never the reverse.
3. **Two derived values agreeing is not verification when they share a source.**
   Cross-checking them feels like confirmation and is not. Verified 2026-08-31: a
   session published a wrong peer socket and a wrong transcript id, both derived
   from one shell's `$PPID`, both consistently pointing at a stranger's session.
   Re-running the derivation returned the same wrong answer every time. When two
   derived values are wrong in the same direction, look for the shared source
   rather than correcting each in place.

4. **Check the subject, not only the method.** Rules 1-3 catch a check that
   answers an adjacent *question*. This is the harder one: a correct,
   well-executed check pointed at the wrong *object*. It passes, and it produces
   a true statement — about something nobody asked about — so nothing surfaces
   to contradict it. Verified 2026-08-31: a rebase was confirmed safe by
   checking that four specific commits survived, and those commits belonged to
   someone else entirely; the verification was sound and the referent was wrong.
   Before reporting a verification, restate what it ran *on* and confirm that
   object is the one in the claim.

   Corollary for negative results: an empty result is evidence only if you know
   the check could have come back non-empty. `git log --author=X` returning
   nothing proves X did not commit only to someone who already knows whether X
   commits at all. Say which fact makes your negative conclusive, or it is not
   one.

The cheap check almost always exists — one `ls -la`, one grep, one `--stat`, one
`git merge-base`. The failure is not that it is expensive; **it is that knowing
the rule does not fire at the moment you type the command.** The `HEAD..origin/main`
mistake above was made one message after writing this section, by the author of
it. Treat the rules as things to run, not things to have read.

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
project file. Label the run `worklog-checkpoint: unavailable — local fallback`
and do not claim a worklog checkpoint.

At compaction, delegation, retry exhaustion, scheduled handoff, or
termination, checkpoint exactly: `state path`, `state fingerprint`, `terminal
status`, `next action`, `typed evidence reference`, and `approval boundary`.
The successor must validate the state and replay the recorded next action
before making a new claim.

## Delegation

- Delegate a bounded lookup, research, or verification question.
- Delegate bulk file creation (>=3 files or repetitive templates) to a
  low-cost mechanical delegate rather than generating in-band on frontier
  orchestrator tokens.
- Include the objective, evidence, constraints, budget, and requested return.
- Require evidence, uncertainty, and one proposed next action.
- Each delegate must call `archive.sh` after writing its result, then emit exactly one status line: `archived <child-slug> <sha>` (where `<sha>` comes from `git -C "$WORKLOG_REPO" log -1 --format=%H`) or `blocked|needs_human|failed <child-slug> <reason>`.
- Reconcile returns into the parent state before any write.

Pass the following headings on the first line of your response: objective, known evidence, constraints, budget. The rest goes after a blank line.
For a cold delegate, pass a compact pack with exactly these headings:
`objective`, `known evidence`, `constraints`, `budget`, and `requested return`.
Do not pass the parent transcript. Require the delegate to return exactly
`evidence`, `uncertainty`, and `next action`; discard prose outside that shape
after checking the evidence against the parent goal.

## Dynamic council escalation

- A running orchestrator may invoke the installed council skill without a new
  user turn when the initialized approval boundary permits multi-agent
  research and a material trigger appears: disagreement, a material
  counterexample, bounded retry failure, or an ambiguous scope/dependency.
- Pause only the affected mutation. Keep the loop state `running`, preserve
  claims and unrelated task progress, and pass the original goal, compact task
  context, trigger, affected mutation, evidence, constraints, one decision
  question, and replay check. Never pass the full parent transcript.
- A council result is advisory. On `verified`, persist its artifact, replay the
  discriminating check, and only then resume normal task progression. The verdict must include `decision: <one-sentence answer>` specifying the chosen path and the exact replay command. On `UNVERIFIED`, use `blocked` or `needs_human` with the exact replay check. Council cannot archive a task or prove loop completion by itself.
- Count escalation as part of the current declared cycle unless the state
  budget explicitly declares it as a separate unit; never advance twice for
  one cycle.

## Terminal outcomes

- `complete`: external evidence proves the goal.
- `blocked`: an external dependency prevents safe progress.
- `needs_human`: ambiguity, authority, or risk requires a decision.
- `budget_exhausted`: the declared ceiling was consumed.
- `cancelled`: the user or host stopped the run.
- `continue_scheduled`: this bounded run ended and a real scheduler owns the
  next wakeup.
