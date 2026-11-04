---
name: loop-engineering
description: "Run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled work. Use for iteration toward a verifiable condition, software engineering factories, context recovery, subagent coordination, or loop/worklog/scheduler selection. Skip one-shot tasks."
---

# loop-engineering

Track goal, evidence, budget, next action, and status with the driver.
The agent chooses and verifies actions. User instructions govern permissions.

## Define done first

Before implementation or delegation, define outcome, checks, and accepting owner
from the user's request and current system. Use [acceptance.md](references/acceptance.md)
for independent expectations, proposal exposure, and the final decision.
Simple work needs one outcome and one check. Required reviews still apply.

## Route

Read only the applicable procedure; all models use this contract.

| Need | Read |
| --- | --- |
| One action and one check | Work directly; no loop state |
| Material uncertainty about scope, effects, or task split | [interrogate.md](references/interrogate.md) before initialization |
| Repeated or resumable work | Driver below; [protocol.md](references/protocol.md) for exact state/effect rules |
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

## Drive one cycle

Invoke with `Use loop-engineering. Goal: <observable outcome>.` Use the loaded
`<skill-dir>`; [resolvers.md](references/resolvers.md) handles unknown paths.
Create `<run-dir>` in system temporary storage, outside the worktree, for state,
gates and logs. [durable-context.md](references/durable-context.md) owns handoffs.

```bash
python3 <skill-dir>/scripts/loop_run.py <run-dir> --goal "<observable outcome>"
python3 <skill-dir>/scripts/loop_run.py <run-dir> \
  --evidence "command: <check> — <result>" --next-action "<next check>"
python3 <skill-dir>/scripts/loop_run.py <run-dir> --stop complete \
  --verification "<evidence-gate verification value>" --evidence "artifact: <ref> — <outcome>"
```

For writes or external effects, declare `--allowed-effect` and `--approval-boundary` at init.
Honor the user's budget and minimum; the default is 20 advances, not tool calls.
`--repo` selects the radar target (default: cwd's Git root); `--project <slug>`
enables the Worklog queue. Neither changes cwd or authorizes dispatch.
Repeat `--evidence` for each record and `--allowed-effect` for each allowed effect.

1. Choose the smallest action from the definition of done and current evidence.
2. Check target and authority under [effects.md](references/effects.md); serialize shared writes.
3. Execute and check the declared outcome. Batch independent reads; inspect each
   result. Repeat checks only for changes, failures, open concerns, or required gates.
4. Save `kind: reference — result` records using `command`, `artifact`, `git`,
   `github`, or `url`. Keep full logs outside state and preserve producer exit codes.
5. Advance once if work remains. Continue while `running`; accept against the
   contract and evidence gate before stopping complete. Other outcomes need the
   [protocol's recovery action](references/protocol.md#terminal-outcomes-and-intervention).

Calls report state, radar and queue; `error=` means a failed or unavailable probe.
Radar samples prove neither continuous monitoring nor isolation. The driver does
not dispatch or schedule. State is in `loop_state.json`, configuration in `run.json`.
Do not hand-edit state or mix raw state writes with an active driver.

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
Call an already-selected owner directly; completion still requires `$evidence-gate`.
