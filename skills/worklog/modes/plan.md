# Mode: `plan`

Produce a verifiable plan for a new task as one Markdown block for a task body or `/worklog spawn`. Compare alternatives and add recovery triggers only where they help the decision.

**Does not run the preamble.** Pure generator — no LDAP, no pull, no writes.

**Env prerequisite (no-preamble mode):** if a pass shells out to `"$WORKLOG_BIN/search.sh"` / `related-search.sh`, set `WORKLOG_BIN` + `WORKLOG_REPO` first (prefer `direnv exec "$WORKLOG_REPO" …`). Empty env is the common cold-session miss.

## When to use

- Non-trivial task (>1h) about to start, no task file yet.
- First approach is ambiguous; worth comparing alternatives before committing.
- Past attempts on similar surfaces stalled or thrashed (see `docs/lessons.md`).

Trivial / single-step work: skip. Use `/worklog sync` directly.

## Steps

1. Parse the free-form task description from the argument verbatim.
2. **Propose a slug** per AGENTS.md grammar: `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. If a Linear ID is mentioned in the task, use `eng-<N>-<desc>`; else bare `<desc>`. No `wip-` prefix. Keep it short, kebab-case, semantically distinct from existing slugs (the user can rename via `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>` if it collides).
3. Build the steps below using available evidence and relevant prior lessons. Do not assume a particular host memory file exists.
4. Emit the structured block as a fenced code block (lang: `markdown`) so the user can select cleanly. The user pastes the **inner content** into `people/$LDAP/active/<slug>.md` — not the wrapping fence. No prose outside the block.

## Tools the passes may reach for

- **Target codebase** → use direct reads or literal search for known locations; invoke `/serena-rg-search` for multi-faceted investigation.
- **Worklog corpus** (prior related tasks, projects to reuse) → `"$WORKLOG_BIN/search.sh" <pattern> [filters]` for body grep, `"$WORKLOG_BIN/related-search.sh" <surface-keyword>...` for shared-surface prior-art. Cheap; run before choosing an approach that touch shared surfaces.
- **Recurring lessons** — reuse relevant lessons when available; do not require host-specific memory setup.

Don't dump every tool into every plan — use them only when the next pass genuinely needs evidence.

## Escalating to council (optional, when available)

Use the available installed `council` owner for an explicit Council/multiple-opinion
request, or a consequential decision still unresolved after checking evidence.
Routine factual audits and the number of possible approaches are not sufficient
triggers. Follow the current owner's trigger and report contract; do not assume
one harness path or a particular verdict schema. If unavailable, state the limit
and continue only the planning work that does not require independent evaluation.

Reuse an applicable existing Council outcome in `## Approaches`, including its
uncertainty and evidence. When loop-engineering also needs the same decision,
share that outcome rather than convening a second Council.

## Build the plan

### 1. Decompose into verifiable steps

Break the goal into ≤7 ordered steps. Each step carries a one-line **verify** criterion: a test, a command + expected output, or an observable artifact. Steps without a verify line don't ship — drop or merge them.

Surface any **load-bearing assumptions** that the verify criteria rely on (versions, paths, access, data shape). Check the cheap ones inline before locking the plan; list the rest under `## Assumptions to verify early` in the output so they fail fast at step 1, not step 6.

### 2. Compare approaches when the choice matters

When plausible alternatives have meaningful tradeoffs, compare 2–3 approaches. Each gets a one-line tradeoff across **cost / risk / reversibility / blast radius**. Pick one. **Name the rejected branches** so recovery can reuse the decision.

Skip this section when alternatives would not change the plan.

### 3. Define recovery triggers where needed

For uncertain or costly steps, name the observable failure that would invalidate
the approach and the next action: inspect missing evidence, revise the plan or use
a viable fallback. If a step fails three times, record the failure and change
approach before another attempt; honor a stricter user retry budget. Routine
steps need no separate recovery ceremony.

## Output template

```
# Plan: <proposed-slug>  <!-- per AGENTS.md slug grammar; rename later via `"$WORKLOG_BIN/checkpoint.sh" <new> --rename=<old>` -->

## Goal
<one-sentence verifiable success criterion>

## Approaches (when useful)
1. **<A>** — <tradeoff>. **PICKED.** Why: <reason>.
2. **<B>** — <tradeoff>. Rejected: <reason>. Fallback if A stalls.
3. **<C>** — <tradeoff>. Rejected: <reason>.

## Next
- [ ] 1. <step> → verify: <check>
- [ ] 2. <step> → verify: <check>
- [ ] ...

## Recovery triggers (when useful)
- At step <K>: <observable failure> → <next action>.

## Assumptions to verify early
- <assumption> (check by: <command/lookup>).
```

`## Next` is named to match AGENTS.md § In-session progress visibility — the checkboxes are the durable plan and `"$WORKLOG_BIN/context.sh" <slug>` will hydrate them into `TaskCreate` / `update_plan` on resume.

## Composing with the task body template

The plan sections are additive to the standard task body template in AGENTS.md, not a replacement. Paste order inside the body:

1. `## Context` (standard, optional but recommended) — the *why*, links to parent slugs / PRs / docs.
2. `## Goal` (from plan) — verifiable success criterion.
3. `## Approaches` (from plan) — decision record, when alternatives matter.
4. `## Next` (from plan, matches standard) — verifiable checkboxes.
5. `## Recovery triggers` (from plan) — escalation triggers.
6. `## Assumptions to verify early` (from plan) — fail-fast preconditions.
7. `## Notes from cheshirecode` (standard, added as work progresses).

The `## Approaches`, `## Recovery triggers`, and `## Assumptions to verify early` headings are plan-mode-specific extensions. Lint doesn't enforce them — they're optional but high-value for `kind: plan` and `kind: design` tasks. Drop any heading that doesn't apply to the specific task.

## Pairings

- `/worklog spawn` — once the plan is locked, generate the handoff prompt; reference the slug, not the plan body.
- `/worklog sync <slug>` — once the plan is pasted into the task file, checkpoint it as the first save.
