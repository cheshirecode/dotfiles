---
name: architecture-advisor
description: Review architecture, diagnose web performance, design bounded load tests, and advise on infrastructure tradeoffs using source and measured evidence. Use for substantive system or capacity decisions, not routine code review or ordinary feature edits.
---

# Architecture advisor

Make the next decision defensible: identify the user's workload and constraints,
locate the boundary that owns the behavior, and separate observations from causes
and claims. Advisory by default; implement only within the user's task authority.
Do not turn a request for advice into a deployment, rewrite, or benchmark campaign.
For a small question, answer with the relevant evidence and uncertainty; do not
require a full architecture report or load test.

## Find the decision and its owner

Start with the requested outcome, current pain, latency/reliability or cost target,
and actual workload. Distinguish page-open experience, API throughput, publication
time, and infrastructure spend. Ask only for missing facts that change the decision;
otherwise state a reversible assumption and inspect available evidence.

Trace the relevant path through source, configuration, tests, and decision records.
Identify who owns each transition: authoring/build, publication/activation, request
handling/auth, storage/CDN, browser, and load generator as applicable. Record the
revision and environment. Check current state before treating historical choices
as constraints. Respect active owners and holds; do not edit shared work casually.

Preserve the contracts that constrain alternatives: authorization freshness,
cache identity, navigation origin, old clients/releases, conditional writes,
rollback and lock ownership. A faster component is not useful if it moves cost
onto another path or breaks those contracts. A source layout, language, framework,
or cloud vendor is a choice to justify, never the default conclusion of this skill.

## Match investigation to the question

- **Architecture or infrastructure advice:** compare the existing design with the
  smallest credible alternative. Explain which work moves where, migration and
  operating cost, failure behavior, and the evidence that would change your choice.
  Separate control-plane permissions/state from cacheable data. Include the cost
  of idle and active capacity, scaling behavior, request/storage/network charges
  when material; verify current provider constraints/prices before quoting them.
- **Performance diagnosis:** follow the observed critical path before tuning a
  plausible hotspot. Distinguish client queues, server waits, CPU, allocation/RSS,
  downstream latency, bandwidth, retries, and activation/coordination time. For web
  experience, inspect the browser waterfall, rendering/interactions and actual
  media/cache behavior; HTML status or server RPS alone cannot answer that question.
- **Experiments and load tests:** read [measurement.md](references/measurement.md).
  Use existing raw artifacts first; run only the smallest authorized experiment
  that distinguishes competing explanations. Fixture success establishes harness
  behavior, not provider capacity or production health.
- **Retrospectives:** reconstruct observable rationale from source, diffs, tests,
  measurements and review records. Distinguish recorded decisions, your inference,
  and unknown causes. Read [boundary-cases.md](references/boundary-cases.md) only
  when migration/preservation or misleading benchmark evidence needs illustration.
  Do not infer private reasoning or lack of review from titles or missing comments.

## Decide with evidence

State the leading hypothesis and a plausible competing explanation when the cause
is uncertain; identify an observation that would distinguish them. Prefer evidence
at the owning boundary over a larger count of unrelated passing tests. If evidence
contradicts the hypothesis, revise it before optimizing further.

Compare representative workloads, including skewed/heavy and balanced cases when
relevant. Report tails, failures and recovery alongside central tendency. Separate
output correctness from performance. A historical implementation or snapshot may
encode the bug; derive preservation checks from the contract, and demonstrate the
old failure where feasible rather than regenerating the oracle from the candidate.

Tie the recommendation to the measured regime and remaining uncertainty. Name
rejected alternatives and the evidence against them, without presenting an
unmeasured alternative as disproven. A decision may be to retain the current
system, instrument first, or run one bounded comparison. Avoid complexity whose
benefit is smaller than its migration, operational or financial cost.

## Deliver proportionately

Lead with the recommendation, then the decisive evidence and tradeoff. Include
source/revision, workload, limitations, and the next validation or rollback gate
needed for the proposed claim. Link detailed artifacts rather than dumping logs.
Keep implemented, tested, deployed and production-verified distinct. Successful
CI or a no-op delivery is not runtime or performance proof. When execution is
requested, finish the authorized checks and cleanup; report concrete blockers
without granting yourself production, IAM, credentials or external-load authority.
