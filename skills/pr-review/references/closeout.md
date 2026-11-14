# CLOSEOUT entry point

Read [preflight.md](preflight.md) first. Post-completion retrospective. Triggers: "tighten up PR #N", "wrap up this PR", "distill the learnings from this PR", "deslop this PR before handoff".

**Skip if:** trivial one-commit PR with no reusable lesson (do the deslop step alone).
For requested distillation during unfinished work, retain its pending checks and
next action; stop after distillation and justified guidance changes. Do not call
the implementation complete or compress away its evidence. No worklog task
tracks this PR → skip step 4 (checkpoint).

## The pipeline (ordered — do not reorder)

The order is load-bearing: you distill learnings (step 1) **before** you compress the worklog (step 4) — compression drops the very iteration rows the learnings live in. You codify (step 2) **before** you checkpoint, so the codified changes and compressed worklog land as their own separate commits.

### 1. Distill reusable learnings

Read the task body and verified diff once. Keep concrete reusable lessons with
their observed failure and applicable scope. Use `council` when requested or
when a concrete unresolved question needs independent evaluation; pass compact
evidence and stop when that question is answered. Avoid automatic review waves.

### 2. Codify each kept learning — triage, don't just note

First simplify or extend an existing rule. Keeping a lesson, or seeing it recur,
does not justify new code. Choose guidance, behavioral coverage, task tracking,
or deletion separately; a PR note alone is not durable adoption.

| Learning shape | Codify as |
|---|---|
| Confirmed uncovered failure with a current production/CI consumer | Extend the smallest behavioral check; add a guard only if existing coverage cannot detect it. |
| A posture/discipline lesson ("split these commits", "verify before X") | **CLAUDE.md rule** or a skill edit. Guidance. |
| Justified unfinished work with a current consumer | **Worklog follow-up task**; preserve the implementation's unfinished status. |
| Speculative, duplicate, or no current consumer | **Drop it.** Remove redundant rules instead of adding machinery. |

For a behavioral addition, name its observable failure, actual consumer and
uncovered behavior. Recurrence alone is insufficient. Prefer removing unnecessary
work to moving it into another job or adding a wrapper.

**Commit-hygiene split (per CLAUDE.md):** a guidance change (CLAUDE.md/README posture) and a behavioral guard (`bin/*.sh`, manifest, hooks) are separate concerns → separate commits, even in one session. Don't bundle a CLAUDE.md rule with a lint script.

### 3. Deslop the PR title/body + tracking tasks

Apply [title-body.md](title-body.md). Reuse unchanged preflight evidence; after edits, rerun the affected checks.

**3e. Evidence recording:** Record the current head SHA, the focused validation commands with pass/fail results, and the green CI run or check set in the PR body or a final PR comment. Keep "evidence complete" distinct from "ready for review": a draft PR is not ready until it is explicitly marked ready after those facts are current.

### 4. Compress + checkpoint the worklog

Only when a Worklog task tracks this PR, resolve `$WORKLOG_BIN` via
`worklog/SKILL.md`. Otherwise skip this step without requiring Worklog setup.

Compress the decided iteration drama out of the task body (drop ToT/Reflexion scaffolding, verified "Assumptions", multi-row iteration tables — git log is the audit trail; keep the decision rationale, lessons, re-runnable commands, `next_action`), then checkpoint it **on its own**: `"$WORKLOG_BIN/checkpoint.sh" <slug>`. Use the plain command — its staged-scope guard is exactly what enforces the single-concern commit. Keep this separate from step-2 codify commits — up to three concerns, up to three commits, never one bundle.
Keep post-merge cleanup and recovery notes in the task, not only the PR body.

**No worklog task:** if step 1 was single-pass distillation from the diff + PR body alone (no worklog task tracks this PR), skip this step. The codify commits from step 2 and the deslop from step 3 are sufficient.

On a non-zero checkpoint exit, read Worklog’s `modes/sync.md` failure rules before retrying. That document owns refusal codes and recovery.

## Closeout output

```
=== distilled learnings ===
  <N kept> / <M proposed>. Mode: <single-pass|council fg|council bg>.
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
