# Paired native harness study — 2026-09-18

The 144-run study did **not establish broad reliability or full cost savings**.
The fixed efficiency instruction produced fewer accepted repairs in each lane.
Fully metered pairs suggest lower token use in Codex and OpenCode, but missing
usage prevents every primary full-cost comparison. No candidate met the
preregistered portable-winner rule, so the instruction is not promoted as a
proven optimization.

The earlier claim was unproven because host smoke tests and the stopped
text/image experiment did not supply a completed, varied, paired repair study.
This study supplies that comparison; its negative and inconclusive results do
not turn into a positive claim merely because all planned trials finished.

[Numerical results and 144-row ledger](native-harness-study-2026-09-18.json)
include model-specific token categories, language/order breakdowns, both clocks,
check outcomes, receipt hashes and all failures. Operational transcripts and
native session identifiers remain private.

## Design and provenance

The [preregistered protocol](../scripts/native_harness/study/PROTOCOL.md) fixed
24 tasks × baseline/candidate × three harnesses, with no paid replacements or
retries. Each native turn had a 120-second ceiling and a 240-second controller
watchdog. The corpus covered eight Python, eight JavaScript, four Bash and four
SQLite repairs. All 24 faulty originals failed calibration; all reference
repairs passed their six cases. Each trial had two public and four additional
controller checks, giving 864 final case evaluations.

Candidate instructions asked for focused reads, useful batching, the smallest
correct edit, verification after repair, and no repeated successful checks or
unchanged reads. Source, contract, tools, model, acceptance criteria and time
budget were otherwise identical. Seed 20260918 assigned adjacent pairs and
exactly 12 candidate-first pairs per lane. Three sequential lanes ran
concurrently on one host; cache state was not reset.

Source froze at `2f14b1b4ed63a023fa729607f7808cd2229aa662`; preregistration was
published to remote main at `112ed00`. Frozen file hashes are in the results.
The current corpus clarifies one ambiguous contract described below; it was
not substituted into the frozen trials or their replay.

| Harness | CLI | Requested model |
| --- | --- | --- |
| Claude Code | 2.1.275 | `claude-haiku-4-5-20251001` |
| Codex | 0.155.0, Homebrew cask | `gpt-5.6-sol` |
| OpenCode | 1.18.31 | `openrouter/anthropic/claude-haiku-4.5` |

Host: macOS 26.2 ARM64, Python 3.14.6, Node v26.8.2, SQLite 3.53.4.
These are paired comparisons within each harness; different models/providers
prevent a causal ranking of the harnesses themselves.

## Reliability

Acceptance required every case, a successful public-verifier call, final edit
scope and Git checks, the requested model, complete usage and valid timing.
This strict endpoint measures the whole execution contract, including receipt
failures. Behavioral success is reported separately.

| Harness | Baseline accepted, 95% Wilson CI | Candidate accepted, 95% Wilson CI | Behavioral passes, baseline/candidate |
| --- | --- | --- | --- |
| Claude | 18/24, 75.0% [55.1%, 88.0%] | 16/24, 66.7% [46.7%, 82.0%] | 18/16 |
| Codex | 23/24, 95.8% [79.8%, 99.3%] | 22/24, 91.7% [74.2%, 97.7%] | 23/22 |
| OpenCode | 17/24, 70.8% [50.8%, 85.1%] | 16/24, 66.7% [46.7%, 82.0%] | 20/17 |

There were 112 accepted trials and 116 behavioral passes. Twenty-five trials
passed a public verifier but failed the final additional cases, illustrating
why public-verifier success alone was insufficient. This count includes the
ambiguous path task; it is not a count of 25 established model defects.

| Harness | Baseline-only / candidate-only acceptances | Exact McNemar p | Conservative 95% difference interval, candidate minus baseline |
| --- | --- | --- | --- |
| Claude | 2 / 0 | 0.50 | −45.2 to +31.5 percentage points |
| Codex | 1 / 0 | 1.00 | −28.5 to +21.6 percentage points |
| OpenCode | 3 / 2 | 1.00 | −42.5 to +35.6 percentage points |

None demonstrated the prespecified five-percentage-point noninferiority margin.
The wide intervals also do not establish that the candidate caused worse
reliability. They use simultaneous 97.5% Wilson marginal intervals, as specified
before outcomes; these conservative intervals are not a power guarantee.

## Tokens and elapsed time

| Harness | Complete original usage receipts, baseline/candidate | Known tokens, baseline/candidate | Full token cost per accepted repair comparison |
| --- | --- | --- | --- |
| Claude | 23/24 / 23/24 | 1,774,980 / 1,677,272 | Unavailable |
| Codex | 24/24 / 23/24 | 2,856,931 / 2,089,472 | Unavailable |
| OpenCode | 20/24 / 22/24 | 2,082,164 / 1,542,346 | Unavailable |

Known token totals are lower bounds wherever receipts are incomplete. Missing
usage is not zero. Codex baseline alone has a complete cost of 124,214 reported
tokens per accepted repair. No full-arm ratio or bootstrap cost interval can
be reported for any paired lane. Token categories differ by provider and are
preserved per trial; native dollar estimates are not invoices, and Codex
subscription usage supplies no per-run bill.

The following descriptive subset includes only pairs with complete original
usage on both sides. Ratios are candidate/baseline; failures with complete
usage stay in the subset. Excluding interrupted or unmetered trials can bias
these numbers, so they do not establish total savings or cost per accepted work.

| Harness | Complete pairs | Median task token ratio | Ratio of subset token sums |
| --- | --- | --- | --- |
| Claude | 23 | 1.021 | 0.921 |
| Codex | 23 | 0.759 | 0.753 |
| OpenCode | 18 | 0.884 | 0.842 |

Setup-inclusive elapsed seconds per accepted repair were 43.49 → 53.46 for
Claude and 64.00 → 50.46 for OpenCode. They include failed attempts, but exclude
research preparation, the controlling agent, and post-study audit/recovery.
They are descriptive native execution costs, not end-to-end project savings.
The Codex candidate time comparison is invalid: its interrupted `sql-paid-totals`
trial recorded 233.951 wall seconds versus 1.361 monotonic seconds, a 232.590-second
clock discontinuity. It failed timing and usage acceptance. The cause was not
established; this is environmental evidence, not a candidate reasoning failure.

## Deviations, recovery and fixes

**Ambiguous path contract.** After ten completed receipts, the first Claude
pair exposed a mismatch: “Empty path returns root” reasonably permits returning
`/srv/data/`, while a hidden case expected `/srv/data`. Before inspecting other
path outcomes, a separate sensitivity analysis was declared excluding that
whole task in both arms and all lanes. Primary inputs and grades stayed frozen.
All six path trials failed the strict evaluator. Excluding them leaves counts
at Claude 18/23 versus 16/23, Codex 23/23 versus 22/23, and OpenCode 17/23 versus
16/23. No noninferiority or complete-cost conclusion emerges. The excluded
548,950 reported tokens and six elapsed times remain disclosed in the data.
The future corpus now explicitly requires root normalization.

**OpenCode export truncation.** Five native exports exited successfully but
returned incomplete JSON through stdout pipes. Reproduction on a retained
session yielded exactly 65,536 bytes through a pipe versus 80,744 valid bytes
through an anonymous regular file. The adapter now uses anonymous temporary
storage, closes it after parsing, and retains only selected model/usage metadata.
A regression control reproduces early-exit truncation above 64 KiB and checks
that private content and a fake key are not retained.

Read-only re-exports recovered 1,104,963 previously absent tokens across those
five trials, without any new inference. Separate sidecars preserve original
receipt hashes and acceptance flags. Three of these trials had passed behavior
but failed original receipt acceptance. The supplementary view has complete
candidate OpenCode usage, but baseline still has an interrupted trial, so its
full cost ratio remains unavailable. Six re-export operations and their elapsed
times are recorded, including the unsuccessful recovery of the interrupted
trial. Two Claude shell trials also timed out; neither was replaced.

## Verification and limits

All 144 scheduled invocations have terminal process and result receipts. An
offline audit replayed all 864 cases from retained repairs using frozen source,
checked repair hashes, CLI/source identity, re-normalized native usage, and
recomputed acceptance: **144 audited, zero discrepancies**. Offline controls
passed **50 tests**, and the repository static suite passed **20 checks**. The
export fix also reconciled a real retained session to 328,855 complete tokens.

This is a small, synthetic, controller-authored, single-file corpus on one host,
with one attempt per arm/task and no independently authored task holdout.
Order balancing cannot remove all shared-cache, provider or host effects.
Confidence intervals do not quantify corpus selection bias or future model
drift. Stronger production claims require representative independent tasks,
complete metering and enough pairs for the chosen reliability margin. No
additional paid study is scheduled by this report.

To replay with the retained private study directory, load the user's Node
environment and run the following from the checkout. These commands make no
model calls. The first two use the frozen controller; the audit verifies its
manifest hashes. Re-export recovery is separate and requires retained native
OpenCode sessions. The public JSON supports numerical inspection without those
private sessions; it does not include full operational transcripts.

```bash
source ~/.zshrc
study_root='<retained-study-directory>'
python3 "$study_root/controller/study/analyze.py" "$study_root"
python3 skills/loop-engineering/scripts/native_harness/study/audit.py "$study_root"
python3 skills/loop-engineering/scripts/native_harness/study/sensitivity.py "$study_root"
python3 skills/loop-engineering/scripts/native_harness/study/recover_usage.py "$study_root"
/bin/bash tests/run.sh static
```
