# Loop protocol

Exact state, effect and escalation rules. The root skill owns the normal driver
cycle; [durable-context.md](durable-context.md) owns checkpoints and handoffs.

## State CLI

Use `scripts/loop_state.py` only outside a concurrently running driver. Its
mutations lock the affected paths and replace state atomically; rejection leaves
existing state bytes unchanged. Malformed CLI usage exits 2; a state-contract
rejection exits 3. Successful operations exit 0.

| Command | Contract |
| --- | --- |
| `init` | Creates running state; refuses overwrite unless explicitly forced |
| `advance` | Appends evidence and consumes one declared unit by default; reaches `budget_exhausted` at the ceiling |
| `finish` | Records one terminal outcome; `complete` requires verification; default consumption is zero |
| `resume --state <terminal> --new-state <successor>` | Creates a distinct successor for a resumable terminal state, inheriting goal and cumulative budget and binding predecessor path/status/SHA-256 |
| `fingerprint` | Validates state and prints its exact-byte SHA-256 |
| `annotate --expect-sha256 <digest>` | Appends corrected evidence without reopening state or resetting budget; stale digest rejects the write |
| `validate` | Checks state schema and transition invariants |
| `show` | Prints the five-field summary; `--json` includes history |

`advance` and `finish` accept `--consume N` for declared units. Account for each
unit once, never by both commands. `finish` clears next action for `complete` and
`cancelled`, which reject `--next-action`; resumable outcomes require it.
Driver `--budget` counts advances, not model tokens, tool calls, or elapsed time.
Use raw state accounting only when the run explicitly needs another unit.

`--quiet` prints one index line; `fingerprint` always prints its digest. Terminal
quiet output shows verification rather than the required recovery action, so read
the saved next action when resuming. Capture the expected fingerprint after the
last valid transition; an unexpected mismatch calls for an ownership check,
not blindly refreshing the digest and retrying.

## Terminal outcomes and intervention

| Status | Meaning |
| --- | --- |
| `complete` | Verified evidence proves this run's accepted goal |
| `blocked` | External dependency prevents progress; include replay action |
| `needs_human` | Required authority or consequential decision is missing |
| `budget_exhausted` | Declared ceiling consumed; no automatic extension |
| `cancelled` | User/host stopped the goal |
| `continue_scheduled` | A verified scheduler owns the next wakeup |

While running, continue authorized work; a progress message is not a stop.
For blocked/needs_human, checkpoint and request the specific intervention.
`resume` accepts only blocked, needs_human, budget_exhausted and continue_scheduled,
requires intervention evidence and next action, and preserves the predecessor.
Treat the intervention as pending until the recorded replay check passes.
`--extend-budget N` needs explicit authorization; an exhausted predecessor requires
an extension. For driver-managed runs, create a new run directory, copy the verified
`run.json` into it, and resume into its `loop_state.json`; use the driver for
subsequent cycles so radar/queue remain enabled. See the executable successor
[example](examples.md). Complete and cancelled states cannot resume. A changed authorized
goal needs a new run, not a goal edit or resume; retain a link to prior evidence.

## Effect boundary

Before a mutation, establish its exact target, authorized effect, applicable
approval boundary, and a check for the intended change. Existing authorization
carries forward; routine reversible implementation choices need no repeated
permission. Pause only the affected action if authority or target is unresolved.

Treat merge, deployment, publication, secret writes, and consequential workflow
transitions according to their actual effects. An approval that releases an armed
automation has that automation's effect; inspect it before acting. Honor known
peer constraints and coupled changes. Permission for one surface does not grant
permission for adjacent data or another worker's checkout.

Batch independent observations; serialize shared mutations under [crew.md](crew.md).
A contradiction stops the affected mutation until the revised approach passes its
discriminating check. The driver records state; it grants no authority and does
not verify external truth, execute actions, dispatch workers, or schedule wakeups.

## Verifying a claim

Check the subject and the question: repository, identity, revision, query and
runtime must match the claim. An empty result needs a known discovery/control
path; an incorrectly scoped query is not negative evidence. A failed or
unlaunchable probe is unavailable evidence, not proof of absence; do not use it
to authorize repair. Two values derived from the same source are not independent
confirmation.

For an uncertain implementation, record the hypothesis, observable falsifier and
replay check once in the task. Report decisions and concise rationale, not private
reasoning. If the result does not discriminate, narrow the next check. Choose
validation proportional to changed behavior and required repository gates.

A regression fixture should fail for the behavior it guards. When checking this,
retain the fixture and substitute the old implementation in an isolated copy;
do not stash away both fix and test. Passing coverage alone is not assertion quality.
Capture the producer status before parsing or summarizing output. `tail` or a JSON
parser succeeding says nothing about the producer. Verdict exits need explicit
classification; see [examples.md](examples.md).

## Escalation

When independent results disagree, a material counterexample appears, bounded
retries fail, or the approach remains consequentially ambiguous, use an available,
authorized council or focused review. Keep unaffected work moving.

Pass the compact objective, evidence, constraints and budget plus trigger,
affected action, one decision question, and replay check. A review returns a
supported decision or an explicit unverified result. Replay its discriminating
check before accepting the conclusion; council prose cannot archive tasks or
satisfy completion. If the needed answer remains unavailable, record the blocker
and recovery action. Count escalation within its declared cycle, never twice.
