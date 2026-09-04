---
name: karpathy-guidelines
description: Reduce common LLM coding mistakes. Use before non-trivial edits, multi-step changes, or refactors — when scope is ambiguous, a simpler approach may exist, or success criteria are unstated. Skip for single-line or mechanical edits.
license: MIT
---

# karpathy-guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

## When to use

- Writing, reviewing, or refactoring code
- Avoiding overcomplication, making surgical changes, surfacing assumptions, defining verifiable success criteria

Skip if: read-only exploration/search with no code being produced or judged.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- If no user is reachable (sub-agent, background loop, scheduled run), do not
  stall: state the assumption explicitly in your output, choose the most
  reversible option, and flag it for the caller.

These rules own code-level assumption discipline. Plan-level interrogation
(one question at a time, options with tradeoffs, a readiness verdict that
gates a loop) is owned by loop-engineering's `references/interrogate.md`;
route there instead of restating it.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### Falsifiable hypotheses for uncertain work

For uncertain multi-step work, make the load-bearing assumption falsifiable before editing:

- `Hypothesis:` the assumption that makes the planned approach valid.
- `Falsifier:` the observation that would disprove or materially change it.
- `Replay check:` the original reproduction or narrow command to rerun after revision.

**Example:**
```
Hypothesis: the auth middleware reads the token from the Authorization header.
Falsifier: the middleware reads a different header or cookie.
Replay check: curl -H "Authorization: Bearer test" /api/protected
```

If observed evidence contradicts a load-bearing assumption or a planned expected result:

1. Stop further mutations.
2. Record the contradiction and invalidate the affected remaining steps; unaffected verified steps may stand.
3. Revise the hypothesis and plan before continuing.
4. Rerun the original reproduction plus affected regression checks.

For an apparent blocker, replay it from a trusted vantage point — a context you control end to end, where the inputs, environment, and command are all visible to you rather than reported by another agent or a cached log — and use a cause-specific discriminating check before stopping. Do not generalize a shared blocker classifier — one reusable rule that labels future failures by cause — until three independent incidents (separate runs that do not share a root cause chain, not three symptoms of one run) exhibit the same machine-detectable cause (one a command's exit code, matched output string, or file state can identify without human judgment).

Do not require this three-field block for trivial, single-path tasks with no meaningful uncertainty.
