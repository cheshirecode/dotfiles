# Interrogate the plan — pre-init gate

Pressure-test a loop goal or implementation plan until it is init-ready.
Adapted from the RPI skill family (rpi-grillme, rpi-plan, rpi-review):
interrogate first, plan second, review with route labels. Here the output
feeds `loop_run.py` flags instead of a planning document.

## When to interrogate

Run this gate before the first `loop_run.py <run-dir> --goal` call when any
of these hold:

- The goal is fuzzy, multi-clause, or uses contested terminology.
- The codebase is absent or too thin to inspect real behavior (greenfield).
- The plan authorizes an irreversible effect (`merge`, `deploy`, `publish`,
  secret writes).
- The run will dispatch 3+ tasks (orchestrator) or concurrent writers (crew).

Skip it when the goal is already one observable condition with a known
check. Record the skip as one evidence line:
`interrogation: skipped — <reason>`.

## Mode routing: self-review or council

- **Self-review (default).** In-band, no extra dispatch. Use when the model
  can answer its own questions from the repo, the tools, or stated
  constraints.
- **`$council`.** Escalate on the compose-table triggers — independent
  results disagree, a counterexample appears, retries fail, scope or
  dependencies are ambiguous — or when the plan authorizes an irreversible
  effect. Pass the smallest escalation pack (objective, evidence,
  constraints, the specific contested question) and replay its decision
  check. If `$council` is unavailable, record
  `optional-skill: skipped — <reason>` and fall back to self-review.

## Interrogation protocol (a user is present)

Ask one question at a time; never batch. For each iteration:

1. Analyze the goal and plan for unknowns, hidden assumptions, and false
   certainty.
2. Ask the most critical blocking question first, in this shape:
   - the question
   - why it matters — the execution consequence if guessed wrong
   - option A — with its tradeoff
   - option B — with its tradeoff
   - the recommended option and why
3. Wait for the answer. Restate it as one concrete decision or constraint.
4. Treat a non-answer as an open unknown. Record it, then ask a narrower
   follow-up.
5. Challenge fuzzy terminology immediately; sharpen each term to one
   canonical meaning before building on it.
6. Stop asking when the readiness checklist below is explicit.

## Self-review protocol (no user available)

Ask the same questions of the code and the constraints. Answer each with
the most defensible option and record it as one evidence line:
`assumption: <decision> — <why this option>`. Two hard limits:

- Do not widen scope by assumption. An assumption that changes effects,
  cost, or data policy is a `--stop needs_human` boundary, not a guess.
- Prefer the answer the repo's own code and tests support over the answer
  that is easiest to implement.

## Findings carry route labels

Every finding routes somewhere; none float free:

| Label | Meaning |
| --- | --- |
| `→ goal` | restate the observable success condition |
| `→ budget` | wrong unit or ceiling; set `--budget` |
| `→ effects` | set `--allowed-effect` / `--approval-boundary` |
| `→ delegation` | crew or orchestrator shape is wrong; load crew.md or orchestrator.md |
| `→ evidence` | a goal clause has no typed evidence plan; decide its check now |
| `→ defer` | out of scope for this run — record the reason |

## Readiness verdict — the exit gate

**Ready** only when all of these are explicit:

- observable goal (one condition a command or artifact can prove)
- budget with unit and ceiling
- allowed effects and approval boundary
- first cycle's action (the first vertical slice)
- an evidence plan: each goal clause names the typed evidence that proves it
- open unknowns listed, each with an owner or a `→ defer` reason

**Not Ready:** name each blocker with its route label and do not init.
When a blocker is not the model's to decide, escalate to `$council` or stop
at the boundary with `needs_human`.

On Ready, feed the verdict pack straight into the driver flags: `--goal`,
`--budget`, `--allowed-effect`, `--approval-boundary`. Keep the pack in the
run directory (system temp), not the worktree, and keep it compact — the
loop state is an index, not a log.

## Mid-loop replan review

On a replan trigger (counterexample, retry exhaustion, scope shift), run one
coherence pass with the same route labels: do goal, evidence, and budget
still trace to each other? A changed goal is a `resume` onto a bound
successor state, never an in-place edit of a running goal, and never a
reopened terminal state.
