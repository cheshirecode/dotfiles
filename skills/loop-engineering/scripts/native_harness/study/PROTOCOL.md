# Native harness comparative study, 2026-09-18

## Question and scope

Does a fixed efficiency instruction reduce native usage per accepted repair
without reducing acceptance on heterogeneous, bounded software repairs?
This is a prospective comparison, not a search for a winning prompt. Negative
and inconclusive results finish the study just as positive results do.

The user authorized 24 tasks x 2 arms x 3 harnesses = 144 native invocations.
Each attempt has a 120-second native-turn ceiling and a 240-second controller
watchdog including setup/cleanup. No paid warmups, replacements or retries.
Infrastructure failures, timeouts, missing receipts and rejected work remain
in the denominator. Existing smoke runs are calibration, not study samples.

## Arms, delivery and order

Baseline and candidate receive identical source, task contract, public checker,
tools, requested model and acceptance criteria in fresh disposable Git repos.
Neither is forced to read an extra packet. Both must call the public verifier.
Only the candidate receives this additional instruction:

> Work economically: inspect the declared source and only the supporting files
> needed for this repair. Batch independent reads when useful. Make the smallest
> correct change. After editing, use the public verifier; repeat it only if a
> failure or a further edit makes another check useful. Avoid rereading unchanged
> files and repeating successful checks. Give a concise final result.

No image transport, model substitution, hidden acceptance hint, or larger
candidate time budget is allowed. Fix the prompt before generating outcomes;
never adapt it to observed results. Task order and AB/BA order are randomized
with seed 20260918. Each harness has one sequential lane; the three lanes may
run concurrently. Pair members are adjacent within their lane. Native cache
state cannot be reset independently; report cache categories and order effects.

Models: Claude `claude-haiku-4-5-20251001`, Codex `gpt-5.6-sol`, OpenCode
`openrouter/anthropic/claude-haiku-4.5`. These are within-harness comparisons;
different providers/models are not interchangeable cost units.

## Corpus and acceptance

Use 24 distinct controller-authored repair fixtures: eight Python, eight
JavaScript, four POSIX-shell/Bash and four SQLite tasks. Include parsing,
boundaries, ordering, state, asynchronous behavior and data integrity. Cases
are split into public examples and additional independently checked cases.
For each fixture, the original implementation must fail at least one check,
and a reference repair must pass every check. Freeze task data, reference
repairs, evaluator and native adapters by SHA-256 before any paid trial.

Acceptance requires every named public and additional check, at least one
successful public-verifier call, edits limited to the declared file, unchanged
Git identity, valid timing within both ceilings, the requested observed model
and complete native usage. Final acceptance runs outside the worker's write
scope. Zero check coverage is an error. Reports distinguish behavioral success
from full protocol acceptance.

The corpus is synthetic and controller-authored. It broadens the earlier
one-task smoke; it is not a random sample of production repositories or an
independently authored benchmark. No production-wide reliability claim follows.
The candidate is fixed before outcomes; all tasks are confirmation of that
fixed hypothesis, not a tuning set. Additional evaluator cases are withheld
from workers but are not an independent task-author holdout.

## Endpoints and decision rules

Primary: accepted attempts / all scheduled attempts, per harness and arm.
Report 95% Wilson intervals, paired discordant outcomes and an exact two-sided
McNemar test. Also report a conservative difference interval derived from
simultaneous 97.5% Wilson intervals for the two marginal proportions. Require
its lower endpoint to exceed -0.05 for a reliability-noninferiority claim.
With 24 pairs, small reliability differences may remain unresolved.

Cost: total reported tokens / accepted repairs, charging failures too. Report
input, cache-read, cache-write and output categories separately where known.
Unknown usage is never zero: any incomplete attempt makes the full-arm cost
endpoint incomplete. Also report paired task token ratios and setup-inclusive
elapsed time. Use 10,000 paired bootstrap resamples, stratified by language,
seed 20260918, for descriptive 95% cost-ratio intervals. Keep pair members
together. No unpaired cross-harness token total is a monetary comparison.

Report native dollar estimates for Claude/OpenCode when complete and consistent.
Codex subscription usage has no per-run invoice, so no actual dollar-saving
claim is available for that lane. Report provider estimates as estimates.

A portable efficiency winner requires reliability noninferiority plus an upper
cost-ratio confidence endpoint below 1 in every harness, with complete receipts.
Do not promote a candidate because its point estimate alone looks favorable.
All other outcomes are mixed, negative or inconclusive with their actual data.
Intervals are descriptive for this fixed corpus; they do not quantify corpus
selection bias, future model drift or production task diversity.

## Evidence and delivery

Retain one immutable result directory per planned invocation and a complete
schedule/ledger, including process status, source hashes, requested/observed
model, named checks, scope/Git evidence, both clocks, usage and error class.
Raw operational receipts remain private. Publish only sanitized aggregate
results, protocol, reproducible corpus/runner and offline controls to remote
main. Verify that remote revision, detach this worktree there, and delete only
the local branch created for this task. No global settings changes are needed.
