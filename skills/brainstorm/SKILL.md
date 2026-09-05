---
name: brainstorm
description: "Generate and evaluate new product or tooling ideas from observed pains. Sources seeds, excludes already-evaluated ideas, dispatches 4 standard research angles, then routes evaluation to council and records outcomes in the worklog vault. Triggers: 'product ideation', 'brainstorm ideas', 'find N new ideas', `/brainstorm`. Not for evaluating one predetermined idea — use council directly."
---

# brainstorm

Turn observed pains into evaluated, recorded product ideas.

This skill owns the ideation recipe only: seed sourcing, novelty
exclusion, the four research angles, the keep-threshold iteration rule,
and the output contract. It does not own evaluation machinery.
`$council` owns discussion, collation, voting, ballot validation, and
tally. Do not restate or re-implement any council rule here.

Convention: `$skill-name` means invoke installed skill `skill-name`;
skip and record the reason if unavailable.

## When to use

- "Find/confirm at least N new product ideas" from a body of work
- Periodic ideation over a repo set, worklog vault, or incident history
- An orchestrator loop needs new validated ideas as input

Skip if: the user already has one specific idea (route to `$council`),
or the ask is a design decision, not idea generation.

## Recipe

1. **Source seeds from observed pains.** Read only pain records: worklog
   vault tasks and postmortems, incident notes, session friction notes,
   repo TODO/FIXME markers. Each seed is two sentences: the observed
   pain, then the smallest tool shape that removes it. Give each seed an
   ID (`S1..Sn`). 6-10 seeds per round is enough. A seed must trace to a
   pain you can cite; do not invent market-shaped ideas with no observed
   instance.
2. **Exclude already-evaluated ideas.** Check the vault's prior idea
   records (for example `projects/*ideas*.md` and `active/idea-*.md`).
   Drop any seed that matches a previously voted idea unless new
   evidence exists; record `excluded: <seed> — evaluated <date>`.
3. **Write the seed list to a run file** in system temp (never the
   repo), one seed per block, with the pain citation.
4. **Dispatch the four standard research angles** as council Stage 1
   agents, one angle each, no cross-talk:
   - **competition** — does a credible tool already own the niche?
     Verdict per seed: saturated / contested / underserved / empty.
   - **demand** — do independent external reports of the pain exist
     beyond our own incident? Cite sources.
   - **feasibility** — which existing assets (own repos first) cover
     part of the build? Size the genuinely new part: small/medium/large.
   - **distribution** — is there a real discovery channel (marketplace,
     registry, plugin list), or pull-only?
   Every angle must return candidate items in council's candidate
   contract (falsifier, verification recipe, evidence state). Angle
   prompts follow the council Stage 1 template.
5. **Hand off to `$council`** for Stage 3 discussion through Stage 6
   tally. Pass the seed file and the four angle reports as Stage 2
   findings. Council's iron laws, ballot validation, and thresholds
   apply unchanged.
6. **Apply the keep-threshold iteration rule.** The run declares a
   target K (default 3) of kept ideas. If the tally keeps fewer than K,
   source NEW seeds (return to step 1; never re-vote the same list) and
   run another round, within the declared loop budget. Stop as
   `blocked` if two consecutive rounds keep zero.
7. **Record outcomes via `$worklog`.** Each kept idea becomes a plan
   task (status `draft`, kind `plan`, with Goal / Approaches / Next
   sections). Record each rejected idea with its rejecting criterion in
   the round's idea log so step 2 can exclude it later.

## Compose

- Inside a `loop-engineering` run: the loop supplies budget, effect
  boundary, and one-line evidence per cycle; this skill supplies steps
  1-7. Record one evidence line per completed step.
- `$which-model`: research angles are cheap-lane work; discussion and
  voting follow council's tiering. Skip with a recorded reason when no
  selector exists.
- No council installed: stop and report; do not substitute a single
  self-review for the vote.

## Anti-patterns

- Do not restate council voting math, iron laws, or ballot formats here
  or in prompts; link the council skill.
- Do not let one agent produce both seeds and verdicts on them.
- Do not re-vote a rejected idea without new evidence.
- Do not write seed or angle artifacts into the repo worktree.
- Do not count QUALIFY-heavy near-misses as kept; the tally decides.
