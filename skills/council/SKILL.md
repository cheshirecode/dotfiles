---
name: council
description: "Karpathy-council-style multi-agent workflow with voting: spawn N sub-agents to research a topic in parallel, cross-pollinate findings via discussion, collate candidate items, then VOTE on each item with explicit karpathy-criterion ballots before concluding. Use when the user invokes `/council`, says \"run a council on X\", \"get multiple opinions on Y\", or asks for an audited research pass. Runs until completion — picks foreground or background dispatch per task scope."
---

# council

Orchestrates Karpathy's LLM-council pattern with two twists:
1. **Five active stages + voting**: research → discussion → candidate collation → structured voting → conclude.
2. **Voting replaces verifier-as-cleanup.** Items must clear a majority APPROVE vote to survive, with hard REJECT votes cited against explicit karpathy criteria. This solves the empirically-observed failure mode where a single synthesis agent **invents items** the verifiers then spend their budget removing.

Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council) (multi-model debate + synthesis). This skill adapts the pattern for a single Claude session using `Agent` sub-agents instead of cross-vendor models.

## When to use

- "Run a council on X" / "get multiple opinions on Y" / `/council <topic>`
- Decisions or research tasks where **single-agent blind-spot risk** is real (architecture choices, library surveys, lessons-from-the-field, vendor comparisons, design critiques).
- Tasks deep enough that **5+ minutes of research per angle** is justified.

Skip if: the question has a clear single right answer, you already know the trade-offs, or the scope is one-shot (just ask one agent).

## Stages

| # | Stage | What | Sub-agents | Sync/async |
|---|---|---|---|---|
| 1 | **Research** | Each angle gets its own sub-agent doing independent research. **Each angle proposes candidate items** in its output. No cross-talk. | 3–5 in parallel | async if any single agent likely >2min, else sync |
| 2 | **Findings** | Orchestrator collects + tags findings per angle. | (none — orchestrator) | sync |
| 3 | **Discussion** | One sub-agent reads ALL findings, flags agreements/disagreements/gaps/contradictions. May propose ADDITIONAL candidate items surfaced by cross-angle gaps. | 1 | sync |
| 4 | **Candidate collation** | One sub-agent gathers **the union of candidate items** proposed by Stage 1 angles + Stage 3 discussion. **No invention authority** — collator may NOT add items not proposed upstream. May only dedupe + normalize phrasing. | 1 | sync |
| 5 | **Voting** | M independent voters (≥3, odd) each fill a **structured ballot** per candidate item: APPROVE / REJECT-with-citation / QUALIFY-with-condition. Voters do not see other voters' ballots. | 3+ in parallel | sync |
| 6 | **Tally + conclude** | Orchestrator counts votes per item. Survivors = majority APPROVE AND zero hard REJECT-with-cited-criterion. Failures move to `Killed by vote` with cited reasons. | (none) | sync |

## Sync vs async — when to spawn background agents

- **Foreground** (default): all stages run inline; small councils (3 research agents, <2min each).
- **Background**: Stage 1 only — if research depth or count makes total research time >10min. Use `Agent(run_in_background=true)` per research angle. Use `Monitor` to track completion. Stages 2-6 always run foreground (they consume stage-1 output, cheap, fast).

Decision rule:
```
if N_research_angles * estimated_minutes_per_angle > 10:
    research_mode = "background"
else:
    research_mode = "foreground"
```

When announcing the decision, use telegraphic format: `<mode> <N×M>min > 10min threshold` (background) or `<mode> <N×M>min ≤ 10min threshold` (foreground). Example: `background 12min > 10min threshold`.

The user can override with `/council --bg X` or `/council --fg X`.

## Iron Laws (refusal conditions — mechanical, not soft norms)

- **NO COLLATOR-INVENTED ITEMS.** Stage 4 collator's output is a strict subset of items proposed by Stage 1 angles or Stage 3 discussion. If the collator emits an item with no `[proposed-by: angle-X | discussion]` tag, the orchestrator drops it before Stage 5. The collator has **zero invention authority**.
- **NO ITEM SURVIVES WITHOUT MAJORITY APPROVE.** An item is kept ONLY if `APPROVE_count ≥ ceil(M_returned / 2 + 1)`. Plurality doesn't suffice. Tie = killed.
- **HARD REJECT VETOES.** Any voter's REJECT vote that cites one of the **karpathy voting criteria** (below) kills the item regardless of APPROVE count. The criterion must be named in the ballot. "I don't like it" is not a valid reject; "REJECT: violates SOLVES-EXTANT-PAIN, no user report on file" is.
- **NO STAGE-6 CONCLUSION WITHOUT M≥2 VOTERS RETURNING.** On voter timeout, recompute `M_returned`. If `M_returned < 2`, the entire list is marked `unverified` and surfaced as such.
- **NO CROSS-ANGLE READS IN STAGE 1.** Every research sub-agent's prompt MUST contain the literal clause "You are research angle N of N. Do not Read, Grep, or Monitor outputs of other angles. Do not coordinate."
- **NO CROSS-VOTER READS IN STAGE 5.** Same independence law for voters — no voter sees a sibling voter's ballot.

## Karpathy voting criteria

Voters cast their ballots against these criteria. A REJECT must cite ≥1. An APPROVE asserts none are violated.

| Criterion | Pass test | Common failure shape |
|---|---|---|
| **TRACES** | Item directly addresses a statement in the user's request or implied need | Synthesis added it "to be complete" |
| **SOLVES-EXTANT-PAIN** | A current observed problem (filed report, broken behavior, user friction) | Speculative; "we might need this" |
| **N-THRESHOLD-MET** | For abstractions/refactors: at least 3 concrete instances of the pattern exist | n=1 or n=2 — premature generalization |
| **COST-PROPORTIONATE** | Implementation cost matches the asserted user value | Multi-day infra for a one-line user need |
| **NON-INFRA-PADDING** | Item is user-visible, not pure tooling-for-future-tooling | "Add a manifest schema" with no consumer using it |

The full ballot per item is one of:
- **APPROVE** — all criteria pass.
- **REJECT: <criterion>, <one-sentence justification>** — explicit veto.
- **QUALIFY: <condition>** — keep only if condition met; condition must be a Stage-3 tension or a verifier-grade fix. Approve-with-conditions counts as 0.5 toward the majority.

## Numeric guidance (orchestrator self-enforces)

- Below 2 sub-agents per stage defeats independence. Above 7 produces noise.
- Voters: **always ≥3, odd, recommended 3 or 5**. 2 voters can deadlock (1-1) which the Iron Laws kill — explicit by design, but odd counts avoid the friction.
- Sub-agent prompts longer than ~800 words signal scope creep — split the angle.

## Recipe

1. **Decompose the topic.** State the question. Pick 3–5 research angles that don't overlap.
2. **Spawn research sub-agents** (Stage 1). Each gets a prompt with their angle's scope + the original question. Each agent's output must include a `Candidate items proposed by this angle:` section so Stage 4 can collate. **Cross-angle isolation clause is mandatory.**
3. **Collect findings** (Stage 2). Read each return; quote-tag the key claims + extract candidate items per angle.
4. **Discussion sub-agent** (Stage 3). Identifies cross-angle tensions AND may propose `Additional candidate items surfaced by cross-angle gaps:`.
5. **Candidate collation sub-agent** (Stage 4). Prompt: "Gather the UNION of candidate items from these angles + the discussion. Dedupe near-identical items keeping the strongest phrasing. **You may not add new items.** Output: numbered list, each with `[proposed-by: <source>]` tag. Items without a proposer tag will be rejected." Output: `=== Stage 4 candidate list ===`.
6. **Voting sub-agents** (Stage 5). M (≥3, odd) parallel voters. Each gets the candidate list + Stage 2 findings + Stage 3 discussion + the **karpathy voting criteria table above** + the original user request verbatim. Prompt template: "For each candidate item, cast a ballot: APPROVE / REJECT: <criterion> + reason / QUALIFY: <condition>. You may not see other voters' ballots." Output: `=== Stage 5 ballots ===` — one block per voter.
7. **Tally + conclude** (Stage 6). Orchestrator counts per item:
   - `approve = count(APPROVE)`
   - `qualified = count(QUALIFY) * 0.5`
   - `support = approve + qualified`
   - `hard_rejects = list of (voter, criterion) for each REJECT`
   - **Survive** iff `support ≥ ceil(M_returned/2 + 1)` AND `hard_rejects is empty`.
   - **Otherwise** → `Killed by vote` with all REJECT criteria cited.

## Run-until-completion behavior

The skill must finish all 6 stages in one invocation. Implementation:
- If foreground mode: walk stages 1→6 inline.
- If background mode for Stage 1: spawn N `Agent(run_in_background=true)` calls; armed `Monitor` watches completion; once all N return, proceed.
- Never partial-return. If a voter fails or times out, retry once, then proceed and recompute `M_returned`.

## Output format

### Status verdict style
When emitting a status verdict (KILLED / SURVIVE / SKIP / RUN), use **telegraphic keyword phrases** — no em-dashes, no full sentences. Format: `STATUS keyword-phrase-describing-reason`. Examples:
- `KILLED hard reject veto N-THRESHOLD-MET`
- `SURVIVE majority approve`
- `SKIP single-agent answer not a council task`
- `RUN multi-angle research justified`

```
=== Council: "<topic>" ===
Mode: <foreground|background>
Angles: <N> · Voters: <M>

=== Stage 1 research ===
  • angle A — 1-line summary
  ...

=== Stage 2 findings ===
  Angle A — top claims:
    1. <claim> (agent A)
    ...
  Candidate items proposed:
    Angle A: A-i1, A-i2
    Angle B: B-i1
    ...

=== Stage 3 discussion ===
  Agreements: <list>
  Disagreements: <list>
  Gaps: <list>
  Additional candidates proposed by discussion: D-i1, D-i2

=== Stage 4 candidate list ===
  1. <item> [proposed-by: A] (or [proposed-by: A+D dedupe])
  2. <item> [proposed-by: B]
  ...
  Collator: 0 items invented · X items deduped

=== Stage 5 ballots ===
  Voter 1:
    item 1: APPROVE
    item 2: REJECT: SOLVES-EXTANT-PAIN — no user report; speculative
    item 3: QUALIFY: only if Stage-3 tension Y resolved
  Voter 2: ...
  Voter 3: ...
  Voters returned: M_returned of M_planned

=== Stage 6 FINAL LIST ===
  1. <item> [proposed-by: A] [vote: 3 APPROVE / 0 REJECT / 0 QUALIFY → SURVIVE]
  2. ...

  Killed by vote:
    - <item> [vote: 1 APPROVE / 2 REJECT(SOLVES-EXTANT-PAIN, N-THRESHOLD-MET) → KILLED]
    - ...

  Status: verified (M_returned ≥ 2) | UNVERIFIED (M_returned < 2)
```

## Meta-orchestration (beyond the 6 stages)

These apply at every stage.

- **Token budget table before fanout.** Before spawning N sub-agents, emit a 1-line budget estimate. Refuse >20k tokens of simultaneous research without explicit user OK.
- **Voter ballot isolation.** Stage 5 voters receive ONLY the Stage 4 candidate list + Stage 2 findings + Stage 3 discussion + criteria table + original user request. Never pass them a sibling voter's ballot, the collator's internal reasoning, or the orchestrator's commentary.
- **Collator has no creative authority.** If the collator outputs an untagged item, the orchestrator drops it and emits a `Collator violation:` log line before Stage 5.
- **Fresh-Agent invocations per stage.** Siblings in the same stage share no parent context beyond their prompt. Across stages, pass only the explicit deliverable.

## Anti-patterns

- **Don't let research agents talk during Stage 1.**
- **Don't let the collator invent items.** This is the load-bearing change vs. the old synthesis-agent design — synthesis agents demonstrably invent items the verifiers then have to remove. Collation + voting eliminates the failure mode by structure.
- **Don't use the same sub-agent for collation AND voting.** Voters must be independent.
- **Don't skip Stage 3 discussion when collation looks easy.** Discussion surfaces gaps the angles missed; without it, the candidate pool is whatever happened to occur to the research agents.
- **Don't auto-pick a side on tied votes.** Ties are killed by Iron Law. Use odd-count voters to avoid them.
- **Don't trust specific post-cutoff claims without a verification pass.** If a research agent returns precise details about something the orchestrator can't recognize (a framework, a release date, a stat), spawn a skeptical-default verifier with WebSearch/WebFetch before promoting the claim.
- **Don't run a council on a one-shot question.** If you'd answer it in 30 seconds yourself, the council is overhead for nothing.

## Pairings

- `Agent` tool — every sub-agent in every stage is an `Agent` call.
- `karpathy-guidelines` — provides the voting criteria. Cast your ballot against Think-Before / Simplicity-First / Surgical-Changes / Goal-Driven; the voting criteria table above is the operational form.
- `worklog plan` — for tasks that produce a planning artifact, feed the council's Stage 6 surviving list as input to `/worklog plan <task>`.

## Examples

### Quick foreground council with voting

```
User: /council "should we adopt MinishLab/semble for code search?"
Claude: 4 angles. Mode: foreground. Voters: 3.
        [Stage 1] 4 angles return findings + 8 candidate items
        [Stage 2] findings tagged · 8 candidates extracted
        [Stage 3] discussion · 1 additional candidate from gap (D-i1) → 9 total
        [Stage 4] collator dedupes A-i2 + B-i1 → 8 candidates · 0 invented
        [Stage 5] 3 voters cast ballots in parallel
        [Stage 6] tally: 5 SURVIVE / 3 KILLED-BY-VOTE
                  Killed citations: 2× SOLVES-EXTANT-PAIN, 1× N-THRESHOLD-MET
```

### Council declines itself

```
User: /council "what's 2+2?"
Claude: Not a council task — single-agent answer in one token. Skipping; 4.
```

## Why voting (vs. synthesis + verification)

A single synthesis agent inventing items + verifiers as cleanup is structurally backwards — items should clear an explicit bar to enter, not enter by default and need removal. Voting flips it: the collator only gathers, voters apply explicit criteria, items need positive support to survive. Fork of Karpathy's original (which used cross-vendor debate); this uses cross-agent voting to surface non-justified inclusion.

- Quick reference: M=3 → threshold 3 (unanimous) · M=5 → threshold 4 · M=7 → threshold 5.
