# Mode: `plan`

Structured upfront plan for a new task. Three reasoning passes — Chain-of-Thought (CoT), Tree-of-Thoughts (ToT), Reflexion — compressed into one markdown block the user pastes into a task body or feeds to `/worklog spawn`.

**Does not run the preamble.** Pure generator — no LDAP, no pull, no writes.

## When to use

- Non-trivial task (>1h) about to start, no task file yet.
- First approach is ambiguous; worth comparing alternatives before committing.
- Past attempts on similar surfaces stalled or thrashed (see `docs/lessons.md`).

Trivial / single-step work: skip. Use `/worklog sync` directly.

## Steps

1. Parse the free-form task description from the argument verbatim.
2. **Propose a slug** per AGENTS.md grammar: `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. If a Linear ID is mentioned in the task, use `eng-<N>-<desc>`; else bare `<desc>`. No `wip-` prefix. Keep it short, kebab-case, semantically distinct from existing slugs (the user can rename via `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>` if it collides).
3. Run the three passes below silently. Recurring lessons (already in Claude memory via `feedback_lessons.md`) apply implicitly — don't re-derive them; do honor them.
4. Emit the structured block as a fenced code block (lang: `markdown`) so the user can select cleanly. The user pastes the **inner content** into `people/$LDAP/active/<slug>.md` — not the wrapping fence. No prose outside the block.

## Tools the passes may reach for

- **Target codebase** (where does X live? does helper Y already exist?) → invoke the `/serena-rg-search` skill. Faster and more accurate than re-deriving from memory; matters most for CoT verify criteria and ToT "is this approach already half-built?" checks.
- **Worklog corpus** (prior related tasks, projects to reuse) → `"$WORKLOG_BIN/search.sh" <pattern> [filters]` for body grep, `"$WORKLOG_BIN/related-search.sh" <surface-keyword>...` for shared-surface prior-art. Cheap; run before locking ToT picks that touch shared surfaces.
- **Recurring lessons** — already in Claude memory (`feedback_lessons.md`); apply implicitly.

Don't dump every tool into every plan — use them only when the next pass genuinely needs evidence.

## Escalating to council (optional, when available)

If `~/.claude/skills/council/SKILL.md` exists AND the task hits either trigger:

- **4+ ToT candidate approaches** with non-trivial trade-offs (your in-head pass would be guessing on the comparison), OR
- **Independent verification matters** (user said "audit this", "second opinion", or the task is irreversible/expensive — architecture choice, vendor selection, migration).

…then invoke `/council "<task description>"` BEFORE this mode's in-head ToT pass. Feed council's Stage 6 final list back as this plan's `## Approaches` section (one bullet per recommendation, picked vs rejected per council's verifier verdicts). The council's per-item verifier verdicts replace the lone-agent confidence rating that ToT would otherwise produce.

**Fallback:** if `~/.claude/skills/council/SKILL.md` doesn't exist (or you'd run `find-skills` and not find it), fall through to the in-head CoT/ToT/Reflexion pass below — no behavior change. Council escalation is a strict upgrade when available, optional otherwise.

## The three passes

### 1. CoT — decompose into verifiable steps

Break the goal into ≤7 ordered steps. Each step carries a one-line **verify** criterion: a test, a command + expected output, or an observable artifact. Steps without a verify line don't ship — drop or merge them.

Surface any **load-bearing assumptions** that the verify criteria rely on (versions, paths, access, data shape). Check the cheap ones inline before locking the plan; list the rest under `## Assumptions to verify early` in the output so they fail fast at step 1, not step 6.

### 2. ToT — enumerate approaches, prune

List 2–3 candidate approaches. Each gets a one-line tradeoff across **cost / risk / reversibility / blast radius**. Pick one. **Name the rejected branches** so future Reflexion can backtrack without re-deriving.

Skip ToT only if exactly one viable approach exists. Be honest — most non-trivial tasks have at least two.

### 3. Reflexion gates — when to stop and rethink

Tie escalation triggers to the CoT steps:

- **Mid-plan check:** after step N (pick a natural midpoint), re-read the plan against `git log --since=<window>`; if any verify failed silently, branch back to ToT.
- **3-strike pivot:** any single step fails 3× → log a one-liner under the task body's `## Notes from cheshirecode` section, then switch to the named fallback branch from ToT. No fourth attempt on the same approach. Promote to `docs/lessons.md` only if the lesson generalizes beyond this task (the lessons ledger is curated — keep it high-signal).

This matches the architectural-question trigger in `systematic-debugging` (3+ failed fixes → question the pattern, don't fix again).

## Output template

```
# Plan: <proposed-slug>  <!-- per AGENTS.md slug grammar; rename later via `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>` -->

## Goal
<one-sentence verifiable success criterion>

## Approaches (ToT)
1. **<A>** — <tradeoff>. **PICKED.** Why: <reason>.
2. **<B>** — <tradeoff>. Rejected: <reason>. Fallback if A stalls.
3. **<C>** — <tradeoff>. Rejected: <reason>.

## Next (CoT)
- [ ] 1. <step> → verify: <check>
- [ ] 2. <step> → verify: <check>
- [ ] ...

## Reflexion gates
- After step <K>: <trigger> → <action>.
- 3-strike pivot: any step fails 3× → log lesson, switch to approach <B>.

## Assumptions to verify early
- <assumption> (check by: <command/lookup>).
```

`## Next` is named to match AGENTS.md § In-session progress visibility — the checkboxes are the durable plan and `"$WORKLOG_BIN/context.sh" <slug>` will hydrate them into `TaskCreate` / `update_plan` on resume.

## Composing with the task body template

The plan sections are additive to the standard task body template in AGENTS.md, not a replacement. Paste order inside the body:

1. `## Context` (standard, optional but recommended) — the *why*, links to parent slugs / PRs / docs.
2. `## Goal` (from plan) — verifiable success criterion.
3. `## Approaches` (from plan) — ToT decision record. Keep the rejected branches; they're load-bearing for Reflexion.
4. `## Next` (from plan, matches standard) — CoT checkboxes.
5. `## Reflexion gates` (from plan) — escalation triggers.
6. `## Assumptions to verify early` (from plan) — fail-fast preconditions.
7. `## Notes from cheshirecode` (standard, added as work progresses).

The `## Approaches`, `## Reflexion gates`, and `## Assumptions to verify early` headings are plan-mode-specific extensions. Lint doesn't enforce them — they're optional but high-value for `kind: plan` and `kind: design` tasks. Drop any heading that doesn't apply to the specific task.

## Pairings

- `/worklog spawn` — once the plan is locked, generate the handoff prompt; reference the slug, not the plan body.
- `/worklog sync <slug>` — once the plan is pasted into the task file, checkpoint it as the first save.
