---
name: karpathy-guidelines
description: Reduce common LLM coding mistakes. Use before non-trivial edits, multi-step changes, or refactors — when scope is ambiguous, a simpler approach may exist, or success criteria are unstated. Skip for single-line or mechanical edits.
license: MIT
---

# karpathy-guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

Skip read-only exploration with no code being produced or judged. Keep trivial changes lightweight.

For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

## 1. Think Before Coding

Before implementing:
- State meaningful assumptions and competing interpretations. Ask when missing
  information changes the implementation; otherwise proceed with a stated,
  reversible assumption.
- Prefer the simpler approach and explain material tradeoffs.
- If no user is reachable (sub-agent, background loop, scheduled run), do not
  stall: state the assumption explicitly in your output, choose the most
  reversible option, and flag it for the caller.

These rules own code-level assumption discipline. Plan-level interrogation
(one question at a time, options with tradeoffs, a readiness verdict that
gates a loop) is owned by loop-engineering's `references/interrogate.md`;
route there instead of restating it.

## 2. Simplicity First

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

## 3. Surgical Changes

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

For multi-step work, pair each step with a check of the requested outcome.
Run the original reproduction and affected regression checks after a fix.

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

Replay apparent blockers from a trusted vantage point with visible inputs,
environment, and commands. Use a cause-specific check before stopping.
Generalize a blocker classifier only after three independent incidents with
separate root causes show the same machine-detectable signal (exit code,
output, or file state).

Do not require this three-field block for trivial, single-path tasks with no meaningful uncertainty.
