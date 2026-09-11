---
name: council
description: "Run multi-angle, audited research with independent voting. Use when the user invokes `/council`, says \"run a council on X\", \"get multiple opinions on Y\", asks for an audited research pass, or an authorized orchestrator escalates a live loop. Runs until completion; auto-selects foreground vs background dispatch by task scope."
---

# council

Resolve `<skill-dir>` as this `SKILL.md` file's directory.

## When to use

- "Run a council on X" / "get multiple opinions on Y" / `/council <topic>`
- Decisions or research tasks where **single-agent blind-spot risk** is real (architecture choices, library surveys, lessons-from-the-field, vendor comparisons, design critiques).
- Tasks deep enough that **5+ minutes of research per angle** is justified.
- An authorized parent orchestrator may invoke council mid-run when its
  material-uncertainty trigger fires; this continues the original scope and is
  not a new user request.

Skip if: the question has a clear single right answer, you already know the trade-offs, or the scope is one-shot (just ask one agent).

If the user says not to use a worklog, do not create, update, or suggest a worklog artifact for this council unless they opt in later.

## Stages

| # | Stage | What | Sub-agents | Sync/async |
|---|---|---|---|---|
| 1 | **Research** | Each angle gets its own sub-agent doing independent research. **Each angle proposes candidate items** in its output. No cross-talk. | 3-5 in parallel | background only if total estimate >10min |
| 2 | **Findings** | Orchestrator collects and tags findings per angle. | (none, orchestrator) | sync |
| 3 | **Discussion** | One sub-agent reads all findings, flags agreements/disagreements/gaps/contradictions, and may propose additional candidate items surfaced by cross-angle gaps. | 1 | sync |
| 4 | **Candidate collation** | One sub-agent gathers the union of candidate items proposed by Stage 1 angles and Stage 3 discussion. **No invention authority**: the collator may only dedupe and normalize phrasing. | 1 | sync |
| 5 | **Voting** | M independent voters (>=3, odd) each fill a structured ballot per candidate item: APPROVE / REJECT-with-citation / QUALIFY-with-condition. Voters do not see other voters' ballots. | 3+ in parallel | sync |
| 6 | **Tally + conclude** | Orchestrator validates ballots, counts support per item, resolves QUALIFY conditions, and publishes an outcome-first final report. | (none, orchestrator) | sync |

## Sync vs async

Default to foreground. Use background for Stage 1 only when
`N_research_angles * estimated_minutes_per_angle > 10`; Stages 2-6 stay
foreground. The user can override with `/council --bg X` or `/council --fg X`.
Announce `<mode> <estimated total>min > 10min threshold` (background) or
`<mode> <estimated total>min <= 10min threshold` (foreground).

## Timeout and retry defaults

- Stage 1 foreground research: wait up to 3 minutes per angle. If an angle times out or fails, retry once with the same angle and a shorter "return findings or explicit no-findings" instruction.
- Stage 1 background research: monitor at 2-3 minute intervals. After 15 minutes without progress from an angle, retry once or mark that angle missing.
- Stage 1 quorum: proceed when at least 2 independent research angles return. If fewer than 2 return after retry, mark the council `UNVERIFIED` and stop before Stage 3.
- Stage 5 voters: wait up to 3 minutes per voter. Retry a timed-out or malformed voter once. If returned voters are fewer than 3 or even after retry, spawn one replacement voter when possible; otherwise mark the council `UNVERIFIED`.
- Close completed or failed sub-agents when their stage output is no longer needed. If background Stage 1 reaches quorum and proceeds, keep monitoring still-running angles until timeout; close them without changing Stage 2 findings if they return after Stage 3 has begun.

## Iron Laws

- **NO COLLATOR-INVENTED ITEMS.** Stage 4 output is a strict subset of items proposed by Stage 1 angles or Stage 3 discussion. Every collated item must cite exact upstream IDs, for example `[proposed-by: A1-i2, D-i1]`. Drop untagged or coarse tags such as `[proposed-by: A]`.
- **NO ITEM KEPT WITHOUT MAJORITY-PLUS-ONE SUPPORT.** An item is kept only if `APPROVE_count + (0.5 * QUALIFY_count) >= ceil(M_returned / 2 + 1)`. `M_returned` must be odd and at least 3. Invalid item ballots never lower the denominator. Plurality and ordinary majority do not suffice. Tie = rejected.
- **HARD REJECT VETOES.** Any voter's valid REJECT vote that cites one of the council voting criteria below rejects the item regardless of APPROVE count. The criterion must be named in the ballot. "I don't like it" is not valid.
- **NO STAGE-6 CONCLUSION WITHOUT ENOUGH VALID VOTES.** For each item, compute support from valid ballots for that item against the full odd `M_returned` threshold. If an item has fewer than 3 valid item ballots after one retry, mark that item `UNVERIFIED`. If most items are `UNVERIFIED`, mark the whole council `UNVERIFIED`.
- **NO CROSS-ANGLE READS IN STAGE 1.** Every research prompt must start with `You are research angle <angle_i> of <angle_count>. Do not Read, Grep, or Monitor outputs of other angles. Do not coordinate.`
- **NO CROSS-VOTER READS IN STAGE 5.** Voters receive only the Stage 4 candidate list, Stage 2 findings, Stage 3 discussion, the council voting criteria, and the original request. No voter sees another voter's ballot.
- **NO APPROVE OVER AN UNRESOLVED MATERIAL COUNTEREXAMPLE.** A voter must not cast `APPROVE` when Stage 3 marks the candidate's counterexample survival status `UNRESOLVED MATERIAL`; use `QUALIFY` with the resolving check or `REJECT` with a voting criterion. A material counterexample is evidence that would change the candidate's Stage 6 keep/reject outcome or invalidate its claimed mechanism. Minor uncertainty stays under the normal voting criteria.

## Council voting criteria

Voters cast ballots against these criteria. A valid REJECT must cite one or more of these names. An APPROVE asserts none are violated.

| Criterion | Pass test | Common failure shape |
|---|---|---|
| **TRACES** | Item directly addresses a statement in the user's request or implied need | Synthesis added it "to be complete" |
| **SOLVES-EXTANT-PAIN** | A current observed problem: filed report, broken behavior, or user friction | Speculative; "we might need this" |
| **N-THRESHOLD-MET** | For abstractions/refactors: at least 3 concrete instances of the pattern exist | n=1 or n=2, premature generalization |
| **COST-PROPORTIONATE** | Implementation cost matches the asserted user value | Multi-day infra for a one-line user need |
| **NON-INFRA-PADDING** | Item is user-visible or directly prevents an observed failure | Tooling-for-future-tooling with no current consumer |

The full ballot per item is one of:

- **APPROVE**: all criteria pass.
- **REJECT: <criterion[, criterion...]>, <one-sentence justification>**: explicit veto using only criteria names from this table.
- **QUALIFY: <condition>**: support worth 0.5 only if the condition is a Stage 3 tension or verifier-grade fix.

Before tallying, validate every ballot:

- Save each returned ballot verbatim and run `python3 <skill-dir>/bin/validate-ballot.py --items <N> --unresolved <item numbers> <ballot-file>` from this skill directory. Treat a non-zero exit as malformed and retry once; do not tally an unvalidated ballot.
- Both numeric arguments are **Stage 4 list positions**, not `A1-i2`/`D-i1` upstream IDs. `--items <N>` is the length of the Stage 4 candidate list. `--unresolved` is the comma-separated positions of every item Stage 3 marked `UNRESOLVED MATERIAL`; it is required, and when there are none you must pass `--unresolved none` rather than omitting the flag. Omitting it is a validator error, not a silent pass — that is what keeps the APPROVE-over-UNRESOLVED-MATERIAL Iron Law enforced.
- Invalid criterion name, missing item, or malformed vote -> retry that voter once.
- `APPROVE` on an `UNRESOLVED MATERIAL` candidate is malformed -> retry that voter once.
- Still invalid after retry -> mark that item ballot `INVALID`, exclude it from support/reject counts, keep the full odd `M_returned` denominator, and mark the item `UNVERIFIED` if fewer than 3 valid item ballots remain.
- QUALIFY condition resolved before conclusion -> count as 0.5 support and state the resolution.
- QUALIFY condition not resolved -> count that ballot as non-support and mark the item `UNVERIFIED` if unresolved conditions determine the outcome. Do not silently count unresolved conditions.

## Numeric guidance

- Independent fanout stages below 2 sub-agents defeat independence. This applies to Stage 1 research and Stage 5 voting, not to the single-agent discussion/collation stages.
- Voters: always >=3, odd, recommended 3 or 5. 2 voters can deadlock (1-1), which the Iron Laws reject.
- Sub-agent prompts longer than about 800 words signal scope creep. Split the angle.
- Quick reference: support threshold is `ceil(M_returned / 2 + 1)` for odd returned voter counts only: M=3 threshold 3, M=5 threshold 4, M=7 threshold 5. M=2 or M=4 is `UNVERIFIED` until a replacement voter restores an odd count.

## Model tiering per stage

Read `references/tiering.md` before choosing a model for a stage: it holds the per-stage tier
mapping, the cheap-token expansion rule, and the escalate-only-after-failure rule.

## Candidate item contract

Every candidate carries the same four fields at every stage — Stage 1 `A<i>-iN`, Stage 3 `D-iN`,
and every Stage 4 entry. Stage 4 drops any item missing one, so a Stage 3 discussion item without
a survival status never reaches the ballot.

- **Falsifier or strongest counterexample** — the observation that would defeat or materially qualify the item.
- **Verification recipe** — the cheapest safe check and its expected discriminating result.
- **Verification evidence** — `PLANNED|EXECUTED-PASS|EXECUTED-FAIL|UNAVAILABLE`, plus an artifact pointer or a reason. Never present a planned check as an executed result; preserve the state and pointer verbatim across stages.
- **Counterexample survival status** — `SURVIVES|REFUTED|UNRESOLVED MATERIAL|UNRESOLVED MINOR`, assigned by Stage 3 to every candidate including its own.

## Execution

Follow the stage order in the Stages table. Before spawning a stage agent, read
`references/templates.md` and use the matching template. Collect Stage 1 IDs
and evidence into Stage 2; carry the four candidate fields unchanged through
Stage 4, with Stage 3 assigning survival status to every candidate, including
its own `D-iN` items. Save returned ballots verbatim to system temporary files.
At Stage 6 apply the validator and tally rules above before reporting.

Finish all six stages in one invocation. Stage 1 alone may run in the background;
wait for quorum or its timeout, then continue foreground. Exhausted retries
permit continuation only under the quorum rules; label incomplete evidence
`UNVERIFIED` rather than returning a partial success.

## Output format

At Stage 6, read [references/report.md](references/report.md) for the
outcome-first report and audit appendix. During execution report only short
stage progress; the final answer is the decision, not the progress log.

## Meta-orchestration

- **Token budget line before fanout.** Before spawning N sub-agents, emit a one-line estimate. Refuse >20k tokens of simultaneous research without explicit user OK.
- **Verify absence claims before voters see them.** Any "verified fact" of absence fed to voters (zero callers, zero tests, unused) must be orchestrator-verified with a concrete search first — one angle's absence claim can be contradicted by another angle's findings, and a REJECT veto resting on an unverified absence claim is invalid. If a veto's factual basis turns out false at tally time, mark the item UNVERIFIED and state the correction rather than honoring the veto.
- **Fresh-agent invocations per stage.** Siblings in the same stage share no parent context beyond their prompt. Across stages, pass only the explicit deliverable.
- **Worklog default.** If the user says no worklog tracking, do not invoke `/worklog plan` or write task notes for that council.

## Stage discipline

Do not reuse the collator as a voter or skip Stage 3 because collation looks easy.
Do not call the majority-plus-one rule "majority approve."
Do not downgrade a material counterexample to minor merely to keep it voteable.
Verify time-sensitive factual claims before feeding them to voters.

## Pairings

- Use the host’s available subagent primitive with independent stage prompts. Never assume another harness’s tool name or custom agent type.
- `$karpathy-guidelines`: the council criteria above operationalize Think-Before, Simplicity-First, Surgical-Changes, and Goal-Driven.
- For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.
- `$worklog`: optionally feed the kept list into `/worklog plan <task>`, subject to the Worklog default above.
