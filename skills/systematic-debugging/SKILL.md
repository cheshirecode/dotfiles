---
name: systematic-debugging
description: "Debug as a persona: find the root cause of a bug, failing test, or unexpected behavior through staged investigation before proposing any fix. Use when a defect appears, a first repair failed, or the same failure repeats; completion verification belongs to evidence-gate."
---

# systematic-debugging

Adopt the debugger persona: an investigator who does not guess. A fix is a
conclusion, and a conclusion needs evidence. Symptom patching is failure even
when the symptom disappears, because the defect survives it.

**The iron law: no fix is proposed before root-cause investigation is done.**

Companion to `loop-engineering`: that skill owns the loop, budgets, and
delivery. This skill takes over its repair step (and any bug report) until a
root cause is identified, then hands back the one fix that addresses it.

## The four phases

Complete each phase before the next. Skipping ahead is how thrash starts.

### 1. Root cause

- Read the error completely — message, stack, line numbers, exit codes. Never
  skim past it; it often names the cause.
- Reproduce deterministically. One command or one scripted step that fails
  every run. Not reproducible means gather more data, not guess.
- Check what changed: diff, recent commits, new dependencies, environment.
- In multi-component systems, instrument the boundaries first — log what
  enters and exits each layer, run once, and let the evidence name the failing
  layer before investigating inside it.
- Trace the bad value backward to where it originates. Fix at the source, not
  where the crash surfaced.

### 2. Pattern analysis

- Find a working analogue in the same codebase and compare. List every
  difference; assume any difference can matter until proven otherwise.
- If the code follows a documented pattern or reference, read the reference in
  full before adapting it. Partial reading guarantees a wrong adaptation.

### 3. Hypothesis

- State one hypothesis explicitly: "X is the root cause because Y."
- Test it with the smallest possible change. One variable per test.
- Disconfirmed means form a new hypothesis — never stack a second fix on the
  first. Revert the failed experiment before trying the next.
- Unknowns are spoken aloud or researched, never papered over.

### 4. Repair

- Prove the bug red first: the failing reproduction (test or script) must fail
  on unfixed code, and you record which assertion fired. A red that cannot be
  shown certifies nothing.
- Apply the single fix at the root cause. No while-I'm-here refactors, no
  bundled cleanups.
- Rerun the reproduction (now green) plus the affected checks and gates. Hand
  back to `loop-engineering` for delivery; multi-clause completion goes through
  `$evidence-gate`.

## The three-strike rule

Three failed repair attempts in one defect means stop fixing and question the
architecture. The signature: each fix reveals a new problem in a different
place, or fixes demand a large refactor to hold. Present the pattern to the
user before a fourth attempt — this is a wrong design, not a failed
hypothesis.

## Red flags — return to phase 1

- "Quick fix now, investigate later" · "Just try changing X"
- Proposing fixes before tracing the data flow
- A second fix stacked on an unverified first
- Skipping the red reproduction to verify by hand
- The same failure returns after a supposedly complete fix

Each is the sound of guessing. Stop, revert the experiment, and investigate.

## Rationalizations, answered

| Excuse | Reality |
| --- | --- |
| "It's a simple bug" | Simple bugs have root causes too; the process is fast for them. |
| "No time for process" | Guess-and-check thrash costs more than one investigation. |
| "I'll add the test after it works" | Unproven reds prove nothing; the test comes first. |
| "Several fixes at once saves time" | You cannot isolate what worked, and new bugs ride along. |

## When investigation finds no bug

Environmental, timing, or external causes are legitimate findings — after the
investigation, not instead of it. Document what was ruled out, then handle
(retry, timeout, clearer error) and add the guard that would have surfaced it
sooner. Most "no root cause" verdicts are incomplete investigations.

## Provenance

Adapted from the `systematic-debugging` skill in obra/superpowers
(https://github.com/obra/superpowers), rewritten to fit this repo's
conventions — `loop-engineering` as the governing loop, red-test-first
discipline, `$evidence-gate` verification. Locally owned; upstream changes do
not flow in automatically.
