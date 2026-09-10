# CLOSEOUT entry point

Read [preflight.md](preflight.md) first. Post-completion retrospective. Triggers: "tighten up PR #N", "wrap up this PR", "distill the learnings from this PR", "deslop this PR before handoff".

**Skip if:** trivial one-commit PR with no lessons worth codifying (do the deslop step alone). Implementation not actually finished → finish it first. No worklog task tracks this PR → skip step 4 (checkpoint).

Resolve `$WORKLOG_BIN` via `worklog/SKILL.md`.

## The pipeline (ordered — do not reorder)

The order is load-bearing: you distill learnings (step 1) **before** you compress the worklog (step 4) — compression drops the very iteration rows the learnings live in. You codify (step 2) **before** you checkpoint, so the codified changes and compressed worklog land as their own separate commits.

### 1. Distill learnings — via `council`

Dispatch `council` on the question: *"What are the durable, reusable learnings from PR #N — bugs whose class recurs elsewhere, missing reusable utilities, config that should be parameterized, guardrail gaps the work exposed?"* Feed it the worklog task body and the diff as context.

Why council and not a single read: a single agent transcribes the lessons that are already labeled and misses the ones that aren't. Council's independent angles surface blind spots, and its voting criteria are the exact filter you need next — `N-THRESHOLD-MET` answers "is this a recurring class worth a guardrail or an n=1 one-off", `SOLVES-EXTANT-PAIN` and `COST-PROPORTIONATE` gate speculative "might need it" learnings out.

Downgrade to a single-pass distillation only for a genuinely small PR — mirror council's own skip rule. Single-pass: read the worklog task body + diff once, ask yourself "what bug class, missing utility, or guardrail gap would the next agent re-discover?" and list them. Apply the same codify triage (step 2) to the list. Skip the voting machinery.

The output you carry forward is council's **kept list**: learnings that cleared the bar.

### 2. Codify each kept learning — triage, don't just note

For **every** kept learning, pick exactly one destination. "Note it in the PR description" is not a destination — that dies on merge.

| Learning shape | Codify as |
|---|---|
| Recurring class (council `N-THRESHOLD-MET` passed) — a bug pattern, a missing lint | **Durable guard**: extend an existing `bin/*.sh`/hook if one fits; add a new one only if none does. Behavioral. |
| A posture/discipline lesson ("split these commits", "verify before X") | **CLAUDE.md rule** or a skill edit. Guidance. |
| A concrete one-off fix/improvement, not yet recurring | **Worklog follow-up task** — a real `next_action` item, not a blocker for this PR. |
| Speculative / n=1 / no current consumer (council would REJECT) | **Drop it.** Don't manufacture infra for a hypothetical. |

Council gates whether a *learning* is kept — not its *destination*. Before writing a **new** script for a kept learning, confirm the destination decision itself clears `COST-PROPORTIONATE` / `NON-INFRA-PADDING`; an n≥3 bug class can still be a follow-up audit rather than a new guard if no cheap static check exists.

**Commit-hygiene split (per CLAUDE.md):** a guidance change (CLAUDE.md/README posture) and a behavioral guard (`bin/*.sh`, manifest, hooks) are separate concerns → separate commits, even in one session. Don't bundle a CLAUDE.md rule with a lint script.

### 3. Deslop the PR title/body + tracking tasks

Apply [title-body.md](title-body.md). Reuse unchanged preflight evidence; after edits, rerun the affected checks.

**3e. Evidence recording:** Record the current head SHA, the focused validation commands with pass/fail results, and the green CI run or check set in the PR body or a final PR comment. Keep "evidence complete" distinct from "ready for review": a draft PR is not ready until it is explicitly marked ready after those facts are current.

### 4. Compress + checkpoint the worklog

Compress the decided iteration drama out of the task body (drop ToT/Reflexion scaffolding, verified "Assumptions", multi-row iteration tables — git log is the audit trail; keep the decision rationale, lessons, re-runnable commands, `next_action`), then checkpoint it **on its own**: `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Use the plain command — its staged-scope guard is exactly what enforces the single-concern commit. Keep this separate from step-2 codify commits — up to three concerns, up to three commits, never one bundle.

**No worklog task:** if step 1 was single-pass distillation from the diff + PR body alone (no worklog task tracks this PR), skip this step. The codify commits from step 2 and the deslop from step 3 are sufficient.

On a non-zero checkpoint exit, read Worklog’s `modes/sync.md` failure rules before retrying. That document owns refusal codes and recovery.

## Closeout output

```
=== distilled learnings (council) ===
  <N kept> / <M proposed>. Mode: <fg|bg>.
  - <learning> → <codify destination>

=== codified ===
  guard:    <bin/xxx.sh change> (commit <sha>)
  guidance: <CLAUDE.md rule>    (commit <sha>)
  task:     <next_action added to <slug>>
  dropped:  <n1 learnings, reason>

=== deslop ===
  #N title: <kept | rewritten: "<new title>"> (derived from <N> commits: <type counts>)
  #N body:  <single-narrative | restructured: dropped N "Also:" sections>
  Leak grep: <clean | fixed at ...>.  Scope re-check: <title+intro cover all streams | corrected>
  Evidence: SHA <hash>, validation: <cmds>

=== checkpoint ===
  <slug>: N → M lines. Commit <sha>. (separate from codify commits)
  [OR: skipped — no worklog task tracked this PR]
```

## Red flags — STOP, you're skipping a step

| Thought | Reality |
|---|---|
| "The lessons are obvious, I'll just list them in the worklog" | That's the baseline failure. Obvious-to-you lessons still evaporate uncodified. Run the distill + codify triage. |
| "Codifying is overkill for this" | Then council would have REJECTED the learning — drop it explicitly, don't skip the triage. |
| "I'll deslop the PR and call it done" | Deslop alone omits this retrospective. You skipped distill + codify — the durable half. |
| "leak-scan came back clean, the body is fine" | It only checks internal references. It cannot see a stale title or a body that reads as two bolted-together streams. The shared title/body procedure also requires judgment no scanner supplies. |
| "The title has a Conv-Commit prefix, so it passes" | A prefix can be valid and stale. `fix(preview):` on a branch that is mostly `perf(ci)` describes one commit of ten. Re-derive it from the final commit set. |
| "I'll put the post-merge/cleanup note in the PR body" | Reviewer-facing text dies on merge. It belongs in the worklog. |
| "One commit for all of it is cleaner" | Guard + guidance + worklog are different diff lenses. Split them (CLAUDE.md commit-hygiene rule). |
| "I'll compress the worklog first, then find the lessons" | Compression drops the rows the lessons live in. Distill FIRST. |
