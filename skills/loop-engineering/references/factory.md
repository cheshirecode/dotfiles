# Software engineering factory

Use when the objective is a repeatable system for producing verified software
changes and improving how they are produced. Keep a single small fix on the
ordinary driver path. A factory can run serially; it does not imply a fleet of
agents, a scheduler, deployment authority, or a new state engine.

## Two loops, separate decisions

The outer loop selects the next eligible deliverable, accepts or returns its
result, and learns from observed production failures. An inner loop works on one
bounded change: perceive current state, plan a falsifiable step, act, observe the
actual result, then reflect against its acceptance checks. Planning text and a
successful tool invocation do not establish a successful change.

Use the existing driver for each resumable loop. Keep the outer budget and
deadline visible to the inner run; cap inner work by the remaining outer budget
and reserve time for verification and handoff. A retry or new worker does not
refresh either budget. On timeout, return partial artifacts and a recovery action;
the parent may select another eligible item but cannot accept the unfinished one.
Use [orchestrator.md](orchestrator.md) for three or more Worklog tasks, and
[crew.md](crew.md) only when delegation is authorized and useful.

## Turn demand into an executable contract

Before implementation, record a compact work order in the existing task store:

- User outcome and observable acceptance checks, including the intended terminal
  stage: locally verified, PR delivered, merged, or deployed and runtime verified.
- Repository, base revision, owned paths, dependencies, and isolated worktree.
- Available tools and effective capabilities: build, test, browser, provider
  access. Probe readiness in the execution boundary that will use the tool. A
  browser working in the controller does not prove it can launch in a sandboxed
  worker. If an authorized controller owns verification, explicitly return its
  observations to the bounded inner loop; do not label them worker-side checks.
- Allowed effects, budget, accepting owner, and the next action on failure.

Translate UI claims into browser behavior: keyboard/focus transitions, request
races, responsive layout, accessibility, and lifecycle cleanup where relevant.
Provide the worker a usable preview/test command and public acceptance examples.
Keep evaluation-only fixtures outside its write scope. A worker denied browser
access cannot demonstrate runtime verification by repeating a typecheck.

## Advance by stage evidence

Apply only the stages the user requested. Existing tool owners perform each
action; this table determines when its result is eligible for the next stage.

| Stage | Required result | If evidence fails or is unavailable |
| --- | --- | --- |
| Specify | Testable work order and ready dependencies/capabilities | Resolve the missing prerequisite or record a concrete blocker |
| Implement | Scoped diff on the recorded base and a bounded attempt return | Diagnose the failing hypothesis; keep unrelated work intact |
| Verify | Changed behavior checked at its actual boundary, plus required regression checks | Return to implementation or repair the test environment; do not weaken acceptance |
| Review/integrate | Findings resolved and checks valid for the proposed head/base/diff | Reconcile current target branch in the isolated worktree and refresh affected evidence |
| Deliver | Evidence for the exact requested terminal stage | Retain the achieved stage and state the outstanding action |
| Improve | Reproducible failure or measured bottleneck tied to a proposed toolkit change | Retain an observation; do not promote it as a rule |

Concurrent sessions may move the integration branch during any stage. Fetch
before integration/push, inspect incoming changes, and reconcile in the owned
worktree. Record the new base/head/diff and rerun affected checks. A remote race
after validation requires reconciliation again; never force-push a shared main.
Do not pull, stash, reset, or clean another session's working tree.

Do not use a weighted score to compensate for failed acceptance checks. Count an
item as accepted only when every required check for its requested stage passes.
An empty queue, report file, green build, or review label cannot substitute for
missing runtime or delivery evidence. The evidence gate checks coverage; the
accepting owner checks relevance, correctness, and revision freshness.

## Retain evidence without accumulating guesses

Use [durable-context.md](durable-context.md) for storage and return envelopes:

- Working context: the current contract, capabilities and next hypothesis;
  rebuild it from fresh state after a reset.
- Attempt history: append an identity, source fingerprint, action/result,
  verification references and decision summary. Preserve failed attempts and
  terminal predecessors; keep large logs outside the compact context.
- Reusable knowledge: only validated lessons with supporting attempts, applicable
  scope and a recheck condition. A successful local observation is not a universal
  fact. Promote into shared skills only when updating that store is authorized.

Check ambiguous external writes through [effects.md](effects.md) before retrying.
Reconcile attempt identities so a duplicate return cannot count as new output.

## Improve the factory with controlled experiments

Separate product work from changing the machinery that judges it. A candidate
may change one guide, tool adapter, task decomposition, or verification method;
freeze acceptance criteria and the evaluator for that comparison. If the
evaluator itself needs repair, recalibrate controls and start a new comparison.
Use [experiments.md](experiments.md) for a comparable scalar objective and bounded
trials; use the ordinary driver for design questions without a comparable metric.

For a software-production comparison, a useful primary metric is the fraction of
fixed work orders accepted at the same requested stage within the same resource
ceiling. Keep correctness, effect boundaries and per-task regressions as hard
gates. Treat elapsed time, actual usage, review rework and escaped defects as
diagnostics, or optimize one after correctness is held constant. Shorter prompts
alone do not establish lower total cost.

Use fresh paired baseline/candidate attempts on representative tasks; retain
failures and unavailable infrastructure separately. Confirm a promising change
on tasks withheld from its proposer. Label small samples and same-family
holdouts accurately. A simulated decision test validates only those decisions;
it does not prove more accepted software, lower cost, or production reliability.
Keep measured winners on the research branch until their authorized integration
checks pass. A keep decision never grants install, push, merge or deploy authority.

### Decision examples

- Typecheck passes; disabling the last modal control loses focus: return the UI
  change to implementation with the failing browser transition as evidence.
- The requested PR exists, but deployment was not requested: report PR delivery;
  do not make deployment a new completion prerequisite.
- A deployment call times out: query its operation and actual target before any
  replay; preserve uncertainty until the effect is reconciled.

This method applies the nested-loop and memory separation from
[Loop Engineering 101](https://dev.to/aairom/loop-engineering-101-83o) to software
delivery. The existing protocol, effect boundary, Worklog and evidence gate own
their invariants; this method connects them rather than duplicating those owners.
