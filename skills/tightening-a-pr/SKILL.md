---
name: tightening-a-pr
description: Use when an agent has just finished the code on a single PR/branch and it's about to be handed to a reviewer — the diff is done but the learnings are still trapped in the worklog and the PR text still reads like an agent transcript. Triggers "tighten up this PR", "wrap up this PR", "distill the learnings from this PR", "codify what we learned", "deslop this PR before handoff", post-PR retrospective. Scoped to ONE just-finished PR, not a periodic multi-PR sweep.
---

# tightening-a-pr

## Overview

When an agent finishes a PR, the code is the easy part to see and the hard part to lose is everything around it: the lessons that only exist in the worklog, the guardrail gaps the work exposed, and a PR title/body that still reads like an agent's iteration log. This skill is the ordered close-out that captures those before handoff.

**Core principle: a learning that isn't codified evaporates on merge.** The point is not to *note* what you learned — it's to turn each learning into something durable (a script check, a CLAUDE.md rule, a follow-up task) or explicitly drop it, so the next agent doesn't re-discover it.

## When to use

- An agent (you, or one you dispatched) just finished the implementation on a single PR/branch and it's pre-handoff.
- The worklog task for it accumulated real exploration — iterations, dead ends, gotchas — and the decision is now made.
- User: "tighten up this PR", "wrap up / close out this PR", "distill and codify the learnings", "deslop before I hand this off".

**Skip / downgrade if:** trivial one-commit PR with no lessons worth codifying (do the deslop step alone). Multiple open PRs to sweep periodically → that's `ship-hygiene`, not this. Implementation not actually finished → finish it first.

## Relationship to ship-hygiene (read this — the overlap is real)

`ship-hygiene` is a **periodic, multi-PR** sweep (CI triage across the stack, "clean my open PRs"). This skill is a **single-PR, post-completion retrospective**. They share exactly one surface — the PR title/body deslop + internal-reference purge — and this skill **delegates that step to ship-hygiene's rules rather than re-deriving the grep patterns.** Do not duplicate ship-hygiene's leak greps here; invoke its guidance for step 3. What this skill adds on top: the council-driven learning distillation (step 1) and the codify triage (step 2), which ship-hygiene has no concept of.

## The pipeline (ordered — do not reorder)

The order is load-bearing: you distill learnings **before** you compress the worklog (step 3 may drop the very rows the learnings live in), and you codify **before** you checkpoint (so the codified changes and the compressed worklog land as their own commits).

### 1. Distill learnings — via `council`

Dispatch `council` on the question: *"What are the durable, reusable learnings from PR #N — bugs whose class recurs elsewhere, missing reusable utilities, config that should be parameterized, guardrail gaps the work exposed?"* Feed it the worklog task body and the diff as context.

Why council and not a single read: a single agent transcribes the lessons that are already labeled and misses the ones that aren't (this is the observed baseline failure). Council's independent angles surface blind spots, and its voting criteria are the exact filter you need next — `N-THRESHOLD-MET` answers "is this a recurring class worth a guardrail or an n=1 one-off", `SOLVES-EXTANT-PAIN` and `COST-PROPORTIONATE` gate speculative "might need it" learnings out.

Downgrade to a single-pass distillation only for a genuinely small PR — mirror council's own skip rule.

The output you carry forward is council's **kept list**: learnings that cleared the bar.

### 2. Codify each kept learning — triage, don't just note

For **every** kept learning, pick exactly one destination. "Note it in the PR description" is not a destination — that dies on merge.

| Learning shape | Codify as |
|---|---|
| Recurring class (council `N-THRESHOLD-MET` passed) — a bug pattern, a missing lint | **Durable guard**: a `bin/*.sh` check, or a `manifest`/hook. Behavioral. |
| A posture/discipline lesson ("split these commits", "verify before X") | **CLAUDE.md rule** or a skill edit. Guidance. |
| A concrete one-off fix/improvement, not yet recurring | **Worklog follow-up task** — a real `next_action` item, not a blocker for this PR. |
| Speculative / n=1 / no current consumer (council would REJECT) | **Drop it.** Don't manufacture infra for a hypothetical. |

**Commit-hygiene split (per this repo's CLAUDE.md):** a guidance change (CLAUDE.md/README posture) and a behavioral guard (`bin/*.sh`, manifest, hooks) are separate concerns → separate commits, even in one session. Don't bundle a CLAUDE.md rule with a lint script.

### 3. Deslop the PR title/body + tracking tasks — via `ship-hygiene`

Apply `ship-hygiene`'s PR-title/body audit and **internal-reference purge** to this one PR: strip worklog slugs/paths, `[POST-MERGE-CLEANUP]`, `next_action`, "Iteration N", "per the audit/critique", "scope chosen", and skill command names (unless the PR changes skill files). Rewrite product-first (what changed for users + why) unless it's pure engineering/infra. Run ship-hygiene's leak grep against **both** the title/body and the diff's added comments. Do the same purge on the tracking worklog task's public-facing fields. Use ship-hygiene's rules verbatim — this skill does not restate them.

### 4. Checkpoint

Checkpoint the worklog body change on its own: `WORKLOG_CHECKPOINT_FORCE=1 "$WORKLOG_BIN/checkpoint.sh" <slug>`. Keep it separate from the step-2 codify commits (guard commit, guidance commit) — three concerns, up to three commits, never one bundle.

## Red flags — STOP, you're skipping a step

| Thought | Reality |
|---|---|
| "The lessons are obvious, I'll just list them in the worklog" | That's the baseline failure. Obvious-to-you lessons still evaporate uncodified. Run the distill + codify triage. |
| "Codifying is overkill for this" | Then council would have REJECTED the learning — drop it explicitly, don't skip the triage. |
| "I'll deslop the PR and call it done" | Deslop alone is ship-hygiene. You skipped distill + codify — the durable half. |
| "I'll put the post-merge/cleanup note in the PR body" | Reviewer-facing text dies on merge. It belongs in the worklog. |
| "One commit for all of it is cleaner" | Guard + guidance + worklog are different diff lenses. Split them (CLAUDE.md commit-hygiene rule). |
| "I'll compress the worklog first, then find the lessons" | Compression drops the rows the lessons live in. Distill FIRST. |

## Anti-patterns

- Re-deriving ship-hygiene's leak greps inline instead of invoking ship-hygiene for step 3.
- Running a full multi-PR CI/comment sweep — that's ship-hygiene's job, not this single-PR close-out.
- Turning every learning into a follow-up task by default (the safe-looking option that codifies nothing durable).
- Running a heavyweight council on a trivial one-commit PR — downgrade to single-pass distillation.
- Bundling the codified guard, the CLAUDE.md rule, and the worklog compress into one commit.

## Pairings

- `council` — step 1 distillation. Its kept list + voting criteria drive step 2's codify triage.
- `ship-hygiene` — step 3 deslop + internal-ref purge (delegated, not duplicated).
- `worklog` — step 4 checkpoint (`checkpoint.sh`); follow-up learnings become `next_action` items.
- `karpathy-guidelines` — "don't refactor what isn't broken": most kept learnings are one-off tasks or drops, not new infra.

## Output format

```
=== distilled learnings (council) ===
  <N kept> / <M proposed>. Mode: <fg|bg>.
  - <learning> → <codify destination>

=== codified ===
  guard:    <bin/xxx.sh change> (commit <sha>)
  guidance: <CLAUDE.md rule>    (commit <sha>)
  task:     <next_action added to <slug>>
  dropped:  <n1 learnings, reason>

=== PR deslop (ship-hygiene) ===
  #N title/body: <de-internalized | clean>. Leak grep: <clean | fixed at ...>.

=== checkpoint ===
  <slug>: N → M lines. Commit <sha>. (separate from codify commits)
```

## Example

```
User: tighten up PR #482 before I hand it off
Claude: [council on "durable learnings from #482" → 3 kept / 5 proposed]
        - abort-signal not propagated (class of bug, N-THRESHOLD-MET) → guard: bin/lint-pr.sh + audit task
        - fake-timer test helper missing (n=1 so far)              → follow-up task
        - backoff cap hardcoded                                     → follow-up task
        [codify: lint guard committed; 2 next_actions added; 0 dropped]
        [ship-hygiene deslop: title → feat(upload): ...; stripped worklog path + "iteration 3"]
        [checkpoint worklog 180 → 60 lines, separate commit]
```
