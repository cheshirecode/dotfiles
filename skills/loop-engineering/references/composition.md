## Compose with installed skills

Select the most specific triggered owner; it supplies the procedure, while this
skill supplies budget, effect boundary, evidence, and replay. Pass only objective,
known evidence, constraints, budget, and requested return. Do not preload skills
or duplicate an owner's rules. With no trigger, record `optional-skill: skipped — <reason>`
and continue without spending a cycle.

| Trigger | Owner | Handoff and replay | Skip when |
| --- | --- | --- | --- |
| multi-faceted search | `$serena-rg-search` | facet + paths; replay search | one literal/known file |
| resume or durable handoff | `$worklog` | context/checkpoint; return task reference | one-shot, no durable task |
| delegation needs a different model lane | `$which-model` | availability check before dispatch | no delegate surface or in-band suffices |
| disagreement, counterexample, failed retries, ambiguous scope/dependencies | `$council` | compact escalation + decision replay | clear answer or known tradeoffs |
| write, review, refactor code | `$karpathy-guidelines` | assumptions + smallest change + checks | read-only exploration |
| multiple observable completion clauses | `$evidence-gate` | typed coverage + gate check | one sufficient check |
| brittle format or recurring classification error | `$example-led-instructions` | 0/1/few-shot gate + smallest test | examples add no reliability |
| open-ended ideas with a keep threshold | `$brainstorm` | seeds + exclusions + K; replay tally | predetermined idea: `$council` |
| multiple PRs or stale Worklog/PR/CI surfaces | `$ship-hygiene` | triggered surfaces + hygiene checks | one short PR, no Worklog activity |
| one PR review or completed-work retrospective | `$pr-review` | PR + optional closeout slug; owner checks | no PR, or unfinished closeout |

Routing example: `multi-repo search with uncertain ownership` → `serena-rg-search` → compact candidate paths plus one replay command; `one known-file lookup` → `optional-skill: skipped — single literal lookup`.


### Optional model routing

Use `$which-model` only when the current harness exposes it and delegation has
materially different requirements. The owner supplies the availability gate and
model-selection procedure. Ask for a model lane, not an unverified exact model.
If no dispatch tool, target skill, or required tool exists, record
`model-routing: skipped — <reason>`; do not spend a cycle on it. When the
harness cannot select a model, routing is advisory-only; never claim a model
switch the harness cannot enforce.

### Optional payload transport

At a provider or tool-output boundary, a capability-gated, fail-open,
recoverable compression (Caveman shrink/Pixel) may be used; read
[references/transport.md](transport.md) before doing so. On missing
capability or no measured win, record `pixel-transport: skipped — <reason>`
and pass bytes unchanged.
