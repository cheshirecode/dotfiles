---
name: council
description: "Karpathy-council-style multi-agent research with voting. Use when the user invokes `/council`, says \"run a council on X\", \"get multiple opinions on Y\", or asks for an audited research pass. Runs until completion; auto-selects foreground vs background dispatch by task scope."
---

# council

## When to use

- "Run a council on X" / "get multiple opinions on Y" / `/council <topic>`
- Decisions or research tasks where **single-agent blind-spot risk** is real (architecture choices, library surveys, lessons-from-the-field, vendor comparisons, design critiques).
- Tasks deep enough that **5+ minutes of research per angle** is justified.

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

- **Foreground** (default): all stages run inline; small councils (3 research agents, <2min each).
- **Background**: Stage 1 only, when `N_research_angles * estimated_minutes_per_angle > 10`. Stages 2-6 always run foreground because they consume Stage 1 output and are cheap.

Decision rule:
```
if N_research_angles * estimated_minutes_per_angle > 10:
    research_mode = "background"
else:
    research_mode = "foreground"
```

When announcing the decision, use telegraphic format: `<mode> <N*x>min > 10min threshold` (background) or `<mode> <N*x>min <= 10min threshold` (foreground). Example: `background 12min > 10min threshold`.

The user can override with `/council --bg X` or `/council --fg X`.

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

Use `$which-model` for provider/model selection. Council owns the stage requirements; `which-model`
owns model comparison, pricing freshness, first-class Chinese-model treatment, data-policy gates,
and sequential-thinking decomposition. If `which-model` is unavailable, use the same principle:
pick the cheapest model lane that clears the stage's capability and data-policy bar.

The council-specific mapping is:

- **Stage 1 research** — mid tier for judgment-bearing angles (design critique, trade-off analysis); cheap tier for purely mechanical inventory/grep angles.
- **Stage 3 discussion** / **Stage 5 voting** — mid tier: adversarial application of the criteria is judgment work, not lookup.
- **Stage 4 collation** — cheap tier: dedupe + tag only, no invention authority (Iron Law), so it needs no reasoning headroom.
- **Stage 6 tally + conclusion** — the frontier orchestrator itself: cross-context judgment, QUALIFY/veto resolution, and the final report stay with the model holding the whole thread.

Cheap-token expansion rule:

- If Stage 1 inventory/search uses a cheap tier, prefer 4-5 narrow angles over 3 broad ones when the extra angle can test a real blind spot.
- If Stage 5 voting uses a cheap-enough mid tier, prefer 5 voters over 3 for high-impact or close-call decisions.
- Keep cheap expansion evidence-shaped: file/line refs, commands, source citations, explicit no-finding results. More cheap tokens are for coverage, not longer prose.

Escalate a stage one tier only after an observed failure (timed-out or malformed return, a voter that can't apply a criterion) — never preemptively. Don't spend frontier/premium budget on a lane a mid model clears, and don't starve cheap tiers when token price makes extra verification affordable.

## Prompt templates

### Stage 1 research

```
You are research angle <angle_i> of <angle_count>. Do not Read, Grep, or Monitor outputs of other angles. Do not coordinate.

Original request: <verbatim user request>
Angle scope: <one narrow, non-overlapping angle>

Read only what is needed for this angle. Return:
1. Top findings with file/line references or source citations when possible.
2. Candidate items proposed by this angle:
   - A<angle_i>-i1: <concrete, testable item>
     - Falsifier or strongest counterexample: <observation that would defeat or materially qualify it>
     - Verification recipe: <cheapest safe check and expected discriminating result>
   - A<angle_i>-i2: <concrete, testable item>
     - Falsifier or strongest counterexample: <observation that would defeat or materially qualify it>
     - Verification recipe: <cheapest safe check and expected discriminating result>
No file edits.
```

### Stage 3 discussion

```
You are the Stage 3 discussion agent. Read all Stage 2 findings below.
Flag agreements, disagreements, gaps, and contradictions.
You may propose additional candidate items only when they are surfaced by cross-angle gaps.
For every candidate, assess its strongest counterexample from the supplied evidence. Run a cheap, safe, in-scope verification recipe only when needed; otherwise leave it unresolved rather than guessing.

Output:
## Stage 3 discussion
Agreements:
Disagreements:
Gaps:
Counterexample survival status:
- A1-i1: <SURVIVES|REFUTED|UNRESOLVED MATERIAL|UNRESOLVED MINOR> — <evidence or missing check>
Additional candidate items surfaced by cross-angle gaps:
- D-i1: <concrete, testable item>
  - Falsifier or strongest counterexample: <observation>
  - Verification recipe: <check and expected result>
```

### Stage 4 candidate collation

```
You are the Stage 4 collator. Gather the union of candidate items from Stage 1 angles and Stage 3 discussion.
Deduplicate near-identical items while keeping the strongest phrasing.
You may not add new items.

Output:
## Stage 4 candidate list
1. <item> [proposed-by: A1-i2, D-i1]
   - Falsifier or strongest counterexample: <preserved from upstream>
   - Verification recipe: <preserved from upstream>
   - Counterexample survival status: <Stage 3 status>
2. <item> [proposed-by: A2-i3]
   - Falsifier or strongest counterexample: <preserved from upstream>
   - Verification recipe: <preserved from upstream>
   - Counterexample survival status: <Stage 3 status>

Collator: 0 items invented; X items deduped.
Items without exact upstream proposer IDs, a falsifier/counterexample, a verification recipe, or a Stage 3 survival status will be dropped before voting.
```

### Stage 5 voting

```
You are an independent Stage 5 voter. You may not see other voters' ballots.
Use only the Stage 4 candidate list, Stage 2 findings, Stage 3 discussion, the council voting criteria, and the original request.
You must not cast `APPROVE` for a candidate marked `UNRESOLVED MATERIAL`; cast `QUALIFY` with the resolving check or `REJECT` with a named criterion. `UNRESOLVED MINOR` remains eligible for normal voting.

For each item, cast exactly one ballot:
- APPROVE
- REJECT: <TRACES|SOLVES-EXTANT-PAIN|N-THRESHOLD-MET|COST-PROPORTIONATE|NON-INFRA-PADDING>[, ...], <one-sentence justification>
- QUALIFY: <condition>

Output:
## Stage 5 ballots
Voter <n>:
  item 1: APPROVE
  item 2: REJECT: SOLVES-EXTANT-PAIN, <reason>
  item 3: QUALIFY: <condition>
```

## Recipe

1. **Decompose the topic.** State the question. Pick 3-5 research angles that do not overlap.
2. **Spawn research sub-agents** (Stage 1). Each prompt must use the Stage 1 template and include the exact no-cross-angle sentence. Each agent output must include `Candidate items proposed by this angle:` plus the required falsifier/counterexample and verification recipe for every item.
3. **Collect findings** (Stage 2). Read each return; quote-tag key claims; extract candidate IDs and their evidence fields per angle.
4. **Run discussion** (Stage 3). Use the Stage 3 template, assign every candidate a counterexample survival status, and record additional `D-iN` candidates only when tied to a cross-angle gap.
5. **Run candidate collation** (Stage 4). Use the Stage 4 template. Drop collator-invented, untagged, or evidence-incomplete items before voting.
6. **Run voting** (Stage 5). Use at least 3 odd-count independent voters. Use the Stage 5 template. Retry malformed voters, including forbidden approvals over unresolved material counterexamples, once.
7. **Tally + conclude** (Stage 6). Validate ballots per item, resolve QUALIFY conditions, enforce majority-plus-one support, apply hard-reject vetoes, and produce the final report.

## Run-until-completion behavior

The skill must finish all 6 stages in one invocation.

- If foreground mode: spawn Stage 1 research agents in parallel and wait up to the foreground timeout, then walk stages 2-6 inline.
- If background mode for Stage 1: spawn N background research agents and monitor until quorum or timeout. Stages 2-6 stay foreground.
- Never partial-return. If retries are exhausted, continue only when quorum rules allow it and mark incomplete evidence as `UNVERIFIED`.

## Output format

### Status verdict style

When emitting a status verdict, use telegraphic keyword phrases. Valid status words are `RUN`, `SKIP`, `KEPT`, `REJECTED`, and `UNVERIFIED`.

Examples:

- `RUN multi-angle research justified`
- `SKIP single-agent answer`
- `KEPT support threshold met`
- `REJECTED hard reject veto N-THRESHOLD-MET`
- `UNVERIFIED insufficient valid ballots`

### Live progress log

During execution, short progress notes are fine:

- `Stage 1 research: 3 angles spawned`
- `Stage 4 candidate list: 12 items, 0 invented`
- `Stage 5 voting: 3 of 3 voters returned`

Do not present the live progress log as the final answer.

### Final report

The final report is outcome-first. The first 25 rendered lines should show the decision summary, not ballots.

## Outcome

| Field | Value |
|---|---|
| Status | `verified` or `UNVERIFIED: <reason>` |
| Mode | `<foreground|background>` |
| Angles | `<returned>/<planned>` |
| Voters | `<returned>/<planned>` |
| Kept | `<count>` |
| Rejected | `<count>` |

## Kept Items

| Item | Source | Approve | Qualify | Reject | Decision | Reason |
|---|---|---:|---:|---:|---|---|
| 1 | A1-i2, D-i1 | 3 | 0 | 0 | KEPT | support threshold met |

## Rejected Items

| Item | Source | Approve | Qualify | Reject | Decision | Reason |
|---|---|---:|---:|---:|---|---|
| 2 | A2-i4 | 2 | 0 | 1 | REJECTED | hard reject veto SOLVES-EXTANT-PAIN |

## Stage Notes

- Stage 1 research: one-line summary per angle.
- Stage 3 discussion: agreements, disagreements, and gaps.
- Stage 4 collation: `0 items invented; X items deduped`.
- Stage 6 tally: support threshold `ceil(M_returned / 2 + 1)` with odd `M_returned >= 3` and at least 3 valid ballots per kept item.

## Audit Appendix

Put full Stage 5 ballots here, after the outcome and vote tables.

## Meta-orchestration

- **Token budget line before fanout.** Before spawning N sub-agents, emit a one-line estimate. Refuse >20k tokens of simultaneous research without explicit user OK.
- **Voter ballot isolation.** Stage 5 voters receive only the Stage 4 candidate list, Stage 2 findings, Stage 3 discussion, criteria table, and original user request.
- **Collator has no creative authority.** If the collator outputs an untagged or coarse-tagged item, drop it before Stage 5 and note the violation.
- **Fresh-agent invocations per stage.** Siblings in the same stage share no parent context beyond their prompt. Across stages, pass only the explicit deliverable.
- **Worklog default.** `worklog plan` is an optional pairing. If the user says no worklog tracking, do not invoke `/worklog plan` or write task notes for that council.

## Anti-patterns

- Do not let research agents talk during Stage 1.
- Do not let the collator invent items.
- Do not use the same sub-agent for collation and voting.
- Do not skip Stage 3 discussion when collation looks easy.
- Do not auto-pick a side on tied votes. Ties are rejected.
- Do not call the majority-plus-one rule "majority approve."
- Do not bury the outcome behind raw ballots.
- Do not keep an item with fewer than 3 valid item ballots.
- Do not count unresolved QUALIFY conditions as support.
- Do not trust specific post-cutoff claims without a verification pass.
- Do not downgrade a material counterexample to minor merely to keep an item voteable.
- Do not run a council on a one-shot question.

## Pairings

- `Agent` tool: every sub-agent in every stage is an `Agent` call when that primitive is available.
- `karpathy-guidelines`: the council criteria above operationalize Think-Before, Simplicity-First, Surgical-Changes, and Goal-Driven.
- `worklog plan`: only when the user has not opted out of worklog tracking. Feed the council's kept list into `/worklog plan <task>` for planning artifacts.

## Examples

### Quick foreground council with voting

```
User: /council "should we adopt MinishLab/semble for code search?"
Claude: RUN multi-angle research justified
        Mode: foreground
        Stage 1 research: 4 angles returned
        Stage 2 findings: 8 candidates extracted
        Stage 3 discussion: 1 additional candidate from gap
        Stage 4 candidate list: 8 items, 0 invented
        Stage 5 voting: 3 of 3 voters returned
        Stage 6 tally: 5 KEPT, 3 REJECTED
        Final report starts with ## Outcome.
```

### Council declines itself

```
User: /council "what's 2+2?"
Claude: SKIP single-agent answer: 4
```

## Why voting

A single synthesis agent inventing items and verifiers cleaning them up is structurally backwards. Items should clear an explicit bar to enter, not enter by default and need removal. Voting flips it: the collator only gathers, voters apply explicit criteria, and items need positive majority-plus-one support to be kept.

- Quick reference: support threshold is `ceil(M_returned / 2 + 1)` for odd returned voter counts only: M=3 threshold 3, M=5 threshold 4, M=7 threshold 5. M=2 or M=4 is `UNVERIFIED` until a replacement voter restores an odd count.
