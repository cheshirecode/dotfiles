# Model guidance

GPT Astra and Claude Fable are first-class users of the same driver, crew and
orchestrator contracts. This reference tunes instructions; it does not select a
model or grant a host capability. Keep a user-requested model/version unchanged.
Verify the active identity through the harness before claiming a model-specific run.

## GPT Astra

Give GPT-6 Astra the outcome, accepted scope and verification criteria. Resolve
routine reversible choices from evidence and continue work already authorized;
ask only for consequential missing input. Explicitly delegate useful independent
work when the host and scope permit it. Audit conflicting skill instructions,
keep communication concise, and stop broadening tests once the required checks
pass unless new evidence calls for more.

This profile follows [OpenAI's Astra guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra).
It adds no hardcoded effort, token, price or context-window settings.

## Sol as orchestrator

Sol can own the whole program: select eligible tasks, claim them, dispatch when
useful, verify returns, checkpoint shared state and advance the driver. Put the
accepted outcome and dependencies in each compact child brief; keep detailed
findings outside the parent history. Use [orchestrator.md](orchestrator.md) for the
same checks regardless of the worker's model.

When available and requested, dispatch Astra or Fable for a difficult implementation
or independent review while Sol continues unrelated coordination. Sol remains
responsible for validating the evidence; a stronger worker's confidence cannot
replace acceptance checks. A worker failure or stale revision returns to Sol for
reconciliation, not an automatic model escalation or budget reset. Without model
selection or dispatch, continue authorized work in-band and disclose that limit.

[Sol's model documentation](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
establishes its tool/structured-output support; actual host exposure still needs
verification. This is a role design, not a claim that every host can dispatch Fable.

## Claude Fable

Give Fable the same outcome and boundaries, with explicit acceptance checks and
brief user-visible progress updates. Ask for findings, decisions and concise
rationale; do not ask it to reproduce private reasoning. Use an independent
verifier for consequential long-running work when dispatch is available.
Remove unnecessary step-by-step scaffolding instead of adding repeated exhortations.
These choices follow [Fable 5 guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5).

For Fable 5.1, batch independent tool requests, keep the lead working when
asynchronous delegates are pending, and preserve scope, decisions and exact
recovery handles during compaction. The host owns API history; a compact task
pack is not permission to edit prior messages or replay thinking blocks against
a changed conversation. Preserve the configured effort unless tuning is requested;
effort names are not equivalent work budgets across models.
See [Fable 5.1 guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1).

## Acceptance before a support claim

Run the same scenarios for each requested model on its actual available harness:
clear authorized work, a material unknown, shared/isolated workers, stale returns,
missing scheduler, and a changed goal. Record model identity, host capabilities,
source revision, actual actions and failures. A role-play by another model is a
document review, not execution proof. OS fixtures likewise establish runtime
portability only. Keep unavailable model runs explicit in delivery evidence.

## Other models

Start from the same outcome, five-field state, ownership, evidence and terminal
contracts. Add scaffolding only for an observed failure, using the smallest
example or narrower task that makes the acceptance check reliable. Do not clone
this skill into per-model policies or assume that provider reputation establishes
context, tools, latency, cost, or quality.

| Observed limitation | Adaptation | Guarantee retained |
| --- | --- | --- |
| No model selector or dispatch | Current model works in-band; report unavailable requested worker | No claimed switch or delegated result |
| Limited effective context | Smaller child briefs and durable recovery handles; load only needed references | User corrections, scope and evidence identity survive |
| Weak structured returns | One short return example; validate fields and ask for missing evidence | A malformed return cannot advance the parent |
| Uncertain plan or inconsistent checks | Narrow the task; use an available authorized verifier or escalate the specific question | Acceptance criteria and budget do not weaken |
| No Python or Bash | Use the host fallback described in hosts.md and label unsupported checks | Manual state is never claimed as verified CLI execution |

Keep the user's selected model/effort unless a change is requested or authorized.
If selection is material and available, use the installed model-routing owner
for a current availability check. Evaluate equivalent tasks and report quality,
retries, cost and latency only when actually measured. Retain this shared design
until repeated failures demonstrate a necessary model-specific exception.
