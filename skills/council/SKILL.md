---
name: council
description: "Karpathy-council-style multi-agent workflow: spawn N sub-agents to research a topic in parallel, cross-pollinate findings, synthesize into one list, then verify with independent sub-agents before concluding. Use when the user invokes `/council`, says \"run a council on X\", \"get multiple opinions on Y\", or asks for an audited research pass. Runs until completion — picks foreground or background dispatch per task scope."
---

# council

Orchestrates Karpathy's LLM-council pattern with a twist: research → discussion → synthesis → verification. Five stages, sub-agents at each, single final list as the deliverable.

Inspired by [Karpathy's LLM Council](https://github.com/karpathy/llm-council) (multi-model debate + synthesis). This skill adapts the pattern for a single Claude session using `Agent` sub-agents instead of cross-vendor models.

## When to use

- "Run a council on X" / "get multiple opinions on Y" / `/council <topic>`
- Decisions or research tasks where **single-agent blind-spot risk** is real (architecture choices, library surveys, lessons-from-the-field, vendor comparisons, design critiques).
- Tasks deep enough that **5+ minutes of research per angle** is justified.

Skip if: the question has a clear single right answer, you already know the trade-offs, or the scope is one-shot (just ask one agent).

## Stages

| # | Stage | What | Sub-agents | Sync/async |
|---|---|---|---|---|
| 1 | **Research** | Each angle gets its own sub-agent doing independent research. No cross-talk. | 3–5 in parallel | async if any single agent likely >2min, else sync |
| 2 | **Findings** | Orchestrator collects + tags findings per angle. | (none — orchestrator) | sync |
| 3 | **Discussion** | One sub-agent reads ALL findings, flags agreements/disagreements/gaps/contradictions. | 1 | sync (cheap input read) |
| 4 | **Synthesis** | One sub-agent produces the **single final list** — combining the discussion notes into actionable items. | 1 | sync |
| 5 | **Verification** | 2–3 independent sub-agents each check the list against the original findings, flag claims unsupported / overstated / wrong. | 2–3 in parallel | sync (focused review) |
| 6 | **Conclude** | Orchestrator merges verifier objections into a final list; surfaces any unresolved disputes to the user. | (none) | sync |

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

The user can override with `/council --bg X` or `/council --fg X`.

## Iron Laws (refusal conditions — mechanical, not soft norms)

- **NO STAGE-6 CONCLUSION WITHOUT N≥2 VERIFIERS RETURNING.** If only one verifier returns (other timed out and retry failed), the entire list is marked `unverified` and surfaced as such; do not silently rubber-stamp.
- **NO STAGE-4 ITEM WITHOUT A `[supports: angle-X claim-Y]` CITATION.** Orchestrator rejects uncited items before passing to Stage 5. Synthesis cannot smuggle invented items.
- **NO CROSS-ANGLE READS IN STAGE 1.** Every research sub-agent's prompt MUST contain the literal clause "You are research angle N of N. Do not Read, Grep, or Monitor outputs of other angles. Do not coordinate." Independence is mechanical, not aspirational.
- **NO AUTO-PICKING SIDES ON DISAGREEMENT.** When verifiers split, output a `Disagreement:` block; never silently arbitrate. (Real example: this skill's own author once flagged a hallucinated framework as suspicious instead of synthesizing it in — that's the discipline.)

## Numeric refusal thresholds

- Spawning `<2` or `>7` sub-agents in a single stage requires an explicit `--allow-N` flag. Below 2 defeats independence; above 7 produces synthesis noise.
- Sub-agent prompts longer than 800 words ≈ scope creep — split the angle.

## Recipe

1. **Decompose the topic.** State the question. Pick 3–5 research angles that don't overlap. Example for "should we adopt library X?": (a) what does it do, (b) license + maintenance status, (c) competing libraries, (d) integration cost with our stack, (e) failure-mode survey from issues + forums.
2. **Spawn research sub-agents** (Stage 1). One per angle. Each gets a self-contained prompt with the angle's scope + the original question for context. Sync or async per the decision rule above. **Cross-angle isolation clause is mandatory** (see Iron Laws). Do NOT pass another agent's transcript into a sibling agent's prompt.
3. **Collect findings** (Stage 2). Read each return; quote-tag the key claims per angle. Output: `=== Stage 2 findings ===` block with one bullet per angle's top 3-5 claims + a one-line "agent claims" attribution.
4. **Discussion sub-agent** (Stage 3). Prompt: "Here are findings from N independent research passes. Identify (a) agreements across angles, (b) disagreements, (c) gaps no angle covered, (d) contradictions." Single sub-agent, focused read. Output: `=== Stage 3 discussion ===`.
5. **Synthesis sub-agent** (Stage 4). Prompt: "Here are findings + discussion. Produce a single list of N concrete items. **Every item MUST end with `[supports: angle-X claim-Y]`**; orchestrator drops uncited items." Output: `=== Stage 4 synthesis (draft) ===`.
6. **Verification sub-agents** (Stage 5). 2-3 of them, parallel. Each gets the draft list + ALL the original findings — and NOTHING from prior verifiers (independence). Prompt: "For each item, return: SUPPORT / QUALIFY / REJECT + cited finding lines." Output: `=== Stage 5 verifications ===` — one block per verifier.
7. **Conclude** (Stage 6). **Quorum rule:** an item is kept only if `support ≥ ceil(M_returned / 2)` AND zero hard rejects. On verifier timeout, recompute `M_returned` (don't reuse the planned `M` — that's how a single rubber-stamper becomes "the council agreed"). Items failing quorum move to `Unresolved:`. Surface disagreements; never silently arbitrate. Output: `=== Stage 6 FINAL LIST ===` + `Unresolved:` tail.

## Run-until-completion behavior

The skill must finish all 6 stages in one invocation. Implementation:
- If foreground mode: walk stages 1→6 inline, calling `Agent` for each sub-agent step. Return only when Stage 6 is written.
- If background mode for Stage 1: spawn N `Agent(run_in_background=true)` calls; armed `Monitor` watches completion; once all N return, proceed to Stages 2-6 in foreground.
- Never partial-return. If a verifier fails or times out, retry once, then proceed with the rest and note the gap in Stage 6 "unresolved".

## Output format

```
=== Council: "<topic>" ===
Mode: <foreground|background>
Angles: <N> · Verifiers: <M>

=== Stage 1 research ===
  • angle A — 1-line summary
  • angle B — 1-line summary
  ...

=== Stage 2 findings ===
  Angle A — top claims:
    1. <claim> (agent A)
    2. ...
  Angle B — top claims:
    ...

=== Stage 3 discussion ===
  Agreements: <list>
  Disagreements: <list>
  Gaps: <list>
  Contradictions: <list>

=== Stage 4 synthesis (draft) ===
  1. <item> — <rationale> [supports: A2, C1]
  2. <item> — <rationale> [supports: B3]
  ...
  (Uncited items dropped by orchestrator; never reach Stage 5.)

=== Stage 5 verifications ===
  Verifier 1: <support|reject|qualify> per item
  Verifier 2: ...
  Verifier 3: ...
  Verifiers returned: M_returned of M_planned (timeouts noted)

=== Stage 6 FINAL LIST ===
  1. <item> — <rationale> [supports: A2, C1] [verifiers: 2/2 SUPPORT]
  2. ...

  Unresolved: <items failing quorum or with hard rejects>
  Status: verified (M_returned ≥ 2) | UNVERIFIED (M_returned < 2)
```

## Meta-orchestration (beyond the 6 stages)

These apply at every stage, not just Stage 1.

- **Token budget table before fanout.** Before spawning N sub-agents, emit a 1-line budget estimate (e.g., `5 angles × ~600 tok prompt × ~1500 tok response ≈ 10.5k`). Refuse to fan out >20k tokens of simultaneous research without explicit user OK.
- **Verifier transcript isolation.** Stage-5 verifiers receive ONLY the Stage-4 synthesis draft + the original Stage-2 findings. Never pass them a Stage-3 discussion summary, a sibling verifier's verdict, or the orchestrator's own commentary. Cross-contamination defeats independence.
- **Duplicate-collapse pass before Stage 6.** Walk the synthesis draft; collapse near-duplicate items keeping the strongest phrasing. Log the dropped twins in an `Internal: deduped X items` line so silent dedup isn't possible.
- **Fresh-Agent invocations per stage.** Sibling sub-agents in the same stage share no parent context beyond their prompt. Across stages, do not pass one stage's full sub-agent transcript into the next; pass only the explicit deliverable (findings list, draft, verdicts).

## Anti-patterns

- **Don't let research agents talk during Stage 1.** Cross-talk defeats the council's blind-spot reduction. Stages 3-5 are where cross-pollination happens.
- **Don't use the same sub-agent for synthesis AND verification.** Verifier must be independent; otherwise it's just rubber-stamping its own draft.
- **Don't skip Stage 3 (discussion) when synthesis looks easy.** The discussion step surfaces contradictions and gaps; synthesis without it produces a happy-path list that misses real tension.
- **Don't auto-pick a side on unresolved disputes.** Surface them to the user. The council's job is to inform, not to silently arbitrate.
- **Don't run a council on a one-shot question.** If you'd answer it in 30 seconds yourself, the council is overhead for nothing.
- **Don't trust specific post-cutoff claims without a verification pass.** If a research agent returns very precise details about something the orchestrator can't recognize (a framework, a release date, a stat), spawn a skeptical-default verifier with WebSearch/WebFetch before promoting the claim. (Inspiration: a real council session where two research agents returned plausible fabricated specifics that a verification pass corrected.)

## Pairings

- `Agent` tool — every sub-agent in every stage is an `Agent` call. Stage 1 may use `run_in_background=true` + `Monitor`; stages 2-6 are inline `Agent` calls.
- `karpathy-guidelines` — apply in stage 6 to reject synthesis items that don't trace to a research finding (Karpathy's "every line should trace to the user's request" — here, every list item should trace to a finding).
- `worklog plan` — for tasks that produce a planning artifact, feed the council's Stage 6 output as input to `/worklog plan <task>`.

## Examples

### Quick foreground council

```
User: /council "should we adopt MinishLab/semble for code search?"
Claude: Decomposing into 4 angles: what-it-does / license + maintenance / competitors (serena, ripgrep, ag) / integration cost.
        [Stage 1] 4 sync sub-agents (~90s each) … done
        [Stage 2] findings tagged
        [Stage 3] discussion sub-agent (~60s) … 2 disagreements, 1 gap
        [Stage 4] synthesis (~60s) … 6 draft items
        [Stage 5] 2 verifiers (~90s parallel) … 5 items supported, 1 qualified
        [Stage 6] final list of 6 (1 qualified) + 1 unresolved
```

### Background research council

```
User: /council "best practices for prompt caching on Anthropic API"
Claude: 6 angles needed (caching basics / cost model / cache hits/misses observed / failure modes / vendor docs / community lessons). Estimated 4min each → background mode.
        [Stage 1] 6 Agent(run_in_background=true) launched. Monitor armed.
        … notifications stream in as each completes …
        [Stages 2-6] foreground after all 6 return.
```

### Council declines itself

```
User: /council "what's 2+2?"
Claude: This isn't a council task — a single agent (me) answers in one token. Skipping; the answer is 4.
```
