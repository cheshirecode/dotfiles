---
name: loop-engineering
description: "Complete one scoped engineering task through definition of done, execution, checks, and authorized delivery in one run. Use for one-shot work and bounded repairs; add durable control only for resumption, coordination, or scheduling."
---

# loop-engineering

Complete one work order in the current run. One-shot execution can include many
tool calls and bounded repairs. User instructions govern scope and permissions.

## One-shot execution

1. Define done: outcome, checks, accepting owner, effects, delivery stage, and
   repair ceiling. Ground expectations in the request and current system;
   [acceptance.md](references/acceptance.md) covers prior proposal exposure and the decision.
2. Check [context capacity](references/context-budget.md#check-every-work-boundary)
   at start, after each tool batch or delegate wave, and before a role switch.
   Then inspect readiness, [trim in-scope tests and logic](references/quality.md#executable-constraints),
   and execute the smallest verifiable unit.
   Check target and authority under [effects.md](references/effects.md); serialize shared writes.
3. Check each unit against the real artifact and revision before proceeding.
   Batch independent reads, inspect every result, and preserve producer exit codes.
4. Repair observed failures within the ceiling. If the same failure repeats,
   test the shared premise before another patch. Retain valid evidence and rerun
   affected checks or required gates.
5. Accept the mechanism and evidence, complete authorized delivery, then report
   the result. Use `$evidence-gate` for multi-clause completion; one sufficient
   check needs no extra gate. Required user and repository reviews still apply.

Continue until the requested outcome is verified or an input, authority, or
budget boundary prevents it. Report an unmet check, cause, and resolving action
at that boundary; leave the outcome unverified.

## Route

Read only the applicable procedure; all models use this contract.

| Need | Read |
| --- | --- |
| One work order | Flow above; no persistent driver state required |
| Material uncertainty about scope, effects, or task split | [interrogate.md](references/interrogate.md) before execution |
| Checkpoint, resume, or scheduler-owned run | Optional driver below; [protocol.md](references/protocol.md) |
| Software factory: intake through improvement | [factory.md](references/factory.md) |
| Harness design, routing patterns, or workflow boundaries | [harness-design.md](references/harness-design.md) |
| Delegates and model lanes | [crew.md](references/crew.md) |
| Three or more Worklog tasks | [orchestrator.md](references/orchestrator.md) |
| Model-specific prompting | [models.md](references/models.md) |
| Tool availability, installation, OS, or recurrence | [hosts.md](references/hosts.md) |
| Native harness execution and usage | [native-harnesses.md](references/native-harnesses.md) |
| Resume, delegation, or compaction | [durable-context.md](references/durable-context.md) |
| Any message to the user | [user-output.md](references/user-output.md) |
| Regression guards, state checks, budgets, or architecture | [quality.md](references/quality.md) |
| Repeated trials judged by one metric | [experiments.md](references/experiments.md) |
| Brittle state/evidence sequencing | [examples.md](references/examples.md) |
| Long session, context filling up | [context-budget.md](references/context-budget.md) |
| Optional output compression | [transport.md](references/transport.md) |

## Durable driver (optional)

Use the driver when checkpointing, resumption, or coordination needs persistent
state. Use [resolvers.md](references/resolvers.md) for unknown skill paths.
Follow [protocol.md](references/protocol.md#durable-driver) for the existing
CLI, budgets, repeated evidence/effect flags, and state rules. A single work order
can finish without driver files or phase-by-phase advances.

Keep transient state and logs outside the worktree;
[durable-context.md](references/durable-context.md) owns persistent handoffs.
Record short `command`, `artifact`, `git`, `github`, or `url` evidence references.
The driver records actions; it does not execute the task, dispatch, or schedule.

Report material progress, evidence, and uncertainty; make the final reply
self-contained. Apply [user-output.md](references/user-output.md) to every message to the user.

## UI feature loops

Before editing, define named `Given / When / Then` cases for each behavior and
relevant regression, with checks, expected results, and target revision/preview.
Prefer executable browser tests.

After committing a clean revision, follow [the UI gate contract](references/ui-feature-gate.md)
and run `python3 <skill-dir>/scripts/ui_feature_gate.py <manifest.json>`.
It builds, verifies applicable preview identity, and checks every case and artifact.
Inspect the artifacts for relevance. Fix failures and rerun the whole cycle;
include the result in the evidence gate.

For manual cases, record actual interactions in the user's main browser and keep
scripted checks unverified. Completion needs runtime evidence for every requested
behavior at that revision. Report a blocked check, its cause, and next action;
leave the outcome unverified.

## Public PR gate

Before each public PR write, prepare title/body locally and scan the exact head.
In dotfiles, run `bin/pr-publication-gate.sh <base-ref> <title-file> <body-file>`.
Elsewhere use the repository secret scan and `pr-review` leak scan.
Inspect names, paths, URLs, and evidence for private context; keep private artifacts
local. Repeat after edits: GitHub retains body history.

## Compose with installed skills

Use [composition.md](references/composition.md) for selection and compact handoffs.
Call an already-selected owner directly; use `$evidence-gate` for multiple completion criteria.

## Optional Slack feedback

When the user explicitly requests ongoing feedback from a Slack thread, use
`$slack-feedback` if installed. It owns the thread cursor, acknowledgements and
case evidence; execute each fixed repair batch with this skill. A thread link or
ordinary read does not activate a watch. Keep watch state separate from the task
journal, and do not create a scheduler without explicit authorization.
