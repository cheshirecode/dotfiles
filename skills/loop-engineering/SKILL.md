---
name: loop-engineering
description: "Run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled work. Use for iteration toward a verifiable condition, context recovery, subagent coordination, or loop/worklog/scheduler selection. Skip one-shot tasks."
---

# loop-engineering

Use the driver to track an observable goal, evidence, budget, next action, and
terminal status. The agent chooses and verifies actions; the driver records them.
User instructions govern scope and authorization; this skill adds no permissions.

## Route

Load only the needed rules. GPT Astra, Sol and Claude Fable use the same workflow;
model guidance tunes its use, while host capabilities determine what can run.

| Need | Read |
| --- | --- |
| One action and one check | Work directly; no loop state |
| Material uncertainty about goal, scope, effects, or task split | [interrogate.md](references/interrogate.md) before initialization |
| Repeated or resumable work | Driver below; [protocol.md](references/protocol.md) for exact state/effect rules |
| Concurrent delegates | [crew.md](references/crew.md) |
| Three or more Worklog tasks | [orchestrator.md](references/orchestrator.md) |
| Astra/Fable prompting, Sol orchestration, or another model | [models.md](references/models.md) |
| Tool availability, installation, OS, or recurrence | [hosts.md](references/hosts.md) |
| Resume, delegation, or compaction | [durable-context.md](references/durable-context.md) |
| Code quality or architectural boundaries | [quality.md](references/quality.md) |
| Brittle state/evidence sequencing | [examples.md](references/examples.md) |
| Optional output compression | [transport.md](references/transport.md) |

## Drive one cycle

Invoke with `Use loop-engineering. Goal: <observable outcome>.`
Resolve `<skill-dir>` to the loaded skill directory; use
[resolvers.md](references/resolvers.md) only if that path is unknown.
Create `<run-dir>` in system temporary storage (`mktemp -d`, `$TMPDIR`, or the
host equivalent). Keep transient state, evidence-gate JSON, logs and snapshots
there, outside the worktree. Durable handoffs follow durable-context.md.

```bash
python3 <skill-dir>/scripts/loop_run.py <run-dir> --goal "<observable outcome>"
python3 <skill-dir>/scripts/loop_run.py <run-dir> \
  --evidence "command: <check> — <result>" --next-action "<next check>"
python3 <skill-dir>/scripts/loop_run.py <run-dir> --stop complete \
  --verification "<evidence-gate verification value>" --evidence "artifact: <ref> — <outcome>"
```

Declare `--allowed-effect` and `--approval-boundary` at init for runs that can
write or affect external systems. Honor the user's budget and any minimum;
the driver defaults to 20 turns. `--repo` selects the radar target (otherwise
cwd's Git root); `--project <slug>` enables the Worklog queue on every cycle.
Neither option changes a tool's cwd or authorizes dispatch.

1. Observe current evidence and choose the smallest useful action.
2. Check the target and existing authorization before a mutation. Apply the
   [effect boundary](references/protocol.md#effect-boundary); serialize shared writes.
3. Execute and verify the changed behavior. Batch independent reads when the
   host supports it; inspect every result. Repeat checks only for new changes,
   failures, unresolved concerns, or a required validation gate.
4. Record one typed line: `kind: reference — result`. Kinds are `command`,
   `artifact`, `git`, `github`, `url`. Keep verbose output in the artifact;
   state is an index, not a log. Preserve producer exit codes.
5. If work remains, advance once and keep working while state is `running`.
   On success, require the evidence gate, then stop complete. Otherwise use the
   protocol's terminal outcome and concrete recovery action.

Each call reports state, radar and queue. `error=` is an unavailable or failed
probe, never a clean radar or empty queue. A radar sample does not monitor the
interval between calls, and a single owner does not prove isolation. The driver
neither delegates work nor schedules wakeups; crew and host guidance own those.
Do not hand-edit state JSON or mix raw state writes with an active driver.

Give brief progress updates when findings or next steps matter. Use concrete
language and the structure the user needs; include essential results in the
final reply even when tool output is hidden. Report decisions, evidence and
uncertainty, rather than private reasoning or a process transcript.

## Compose with installed skills

`$skill-name` means invoke that installed owner when its trigger applies. Pass
objective, evidence, constraints, budget, and requested return. Do not preload
owners or duplicate their procedures. Missing optional owners are skipped;
report a missing required capability with the affected check. Skips cost no cycle.

| Trigger | Owner | Handoff and replay | Skip when |
| --- | --- | --- | --- |
| Multi-faceted code search | `$serena-rg-search` | Search scope and replay command | Known-file lookup |
| Durable work or handoff | `$worklog` | Task context and checkpoint reference | No persistence needed |
| Delegate needs a different model lane | `$which-model` | Preserve requested model; verify availability before dispatch | No selection or dispatch capability |
| Material disagreement or uncertain approach | `$council` | Decision question and discriminating replay check | Evidence resolves the issue |
| Nontrivial implementation | `$karpathy-guidelines` | Scope, assumptions and behavior checks | Read-only observation |
| Completion evidence | `$evidence-gate` | Criteria mapped to verified evidence | One action with one sufficient check |
| Brittle reusable instructions | `$example-led-instructions` | Smallest example set and acceptance scenario | Standard prose suffices |
| Open-ended ideation | `$brainstorm` | Sources, exclusions and acceptance target | Predetermined idea |
| Multi-PR cleanup | `$ship-hygiene` | Explicit PR scope and refreshed state | One PR |
| PR review or closeout | `$pr-review` | PR identity and task evidence | No PR or unfinished implementation |
