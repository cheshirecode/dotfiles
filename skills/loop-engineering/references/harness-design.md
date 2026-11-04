# Harness design patterns

Use for requested harness architecture work. Reuse existing owners before adding
agents or orchestration code.

| Work shape | Pattern | Existing procedure |
| --- | --- | --- |
| One scoped work order | One owner executes and checks verifiable units through delivery | [Default flow](../SKILL.md#one-shot-execution) |
| Known request with one owner | Thin router selects that owner | [Skill composition](composition.md) |
| Fixed phases with known inputs | Workflow plan sequences existing specialists | [Work order](factory.md#turn-demand-into-an-executable-contract) and [stage checks](factory.md#advance-by-stage-evidence) |
| Independent branches worth the dispatch cost | Parallel workers with one accepting parent | [Crew](crew.md#ownership-and-dispatch) |
| Decisions depend on earlier results | One lead plans and revises from evidence | [Driver protocol](protocol.md) |

A thin router owns selection, readiness checks, and handoff. Specialists own domain
decisions. Use existing deterministic checks for stable routing where available.
Do not describe model-directed planning as deterministic. Load the selected owner's
domain instructions when needed. Preserve accepted shared decisions and constraints
in the [handoff](durable-context.md#compact-pack).

The existing [retry](crew.md#failed-calls-and-retries), [effect](effects.md), and
[return](durable-context.md#accept-a-return-or-restart) contracts still apply.
Driver advances are not host-enforced token or tool-call caps. Use the host's
actual controls before claiming those limits. Keep trace data within the
[existing privacy boundary](durable-context.md#compact-pack).

## Source scope

The one-shot flow extracts verifiable units, real-artifact proof, premise checks
after repeated failures, and effect reconciliation from
[pstack](https://github.com/cursor/plugins/tree/180939f9e59cc9512e9330649175763e81fad16f/pstack).
Its setup, model defaults, review panels, and permission rules are not imported.

This map applies the public excerpts of
[Agents are microservices](https://read.bytesizeddesign.com/p/agents-are-microservices-that-think)
and [the thin orchestrator](https://read.bytesizeddesign.com/p/meta-thin-orchestrator-agent-router).
Subscription-only sections were not read. The public
[Meta case](https://engineering.fb.com/2026/10/19/ml-applications/thin-orchestrator-ai-agent-architecture/)
supports fixed workflows that reuse specialists and load domain knowledge on demand.
Its results are case-specific. Use [matched measurements](context-budget.md#verify-a-saving),
not published ratios, for local cost or quality claims.
