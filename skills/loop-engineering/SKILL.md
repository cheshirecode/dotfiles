---
name: loop-engineering
description: Design and run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled engineering and research work. Use when an agent must iterate toward a verifiable condition, recover across context boundaries, coordinate subagents, or decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler. Skip trivial one-shot tasks.
---

# Loop Engineering

Use deterministic state transitions around agent judgment. Repeated prompting is
not a loop design.

## Route

1. Skip this skill when one action plus one check is sufficient.
2. For interactive, resumable, or delegated loops, use the state script below.
3. For scheduled loops, also read [references/hosts.md](references/hosts.md) and
   require a real, authorized recurrence primitive.
4. For exact transition, effect, worklog, or handoff rules, read
   [references/protocol.md](references/protocol.md).

## Initialize through the script

Resolve `<skill-dir>` as this `SKILL.md` file's directory. Choose an explicit,
authorized state path; do not hand-edit its JSON.

```bash
python3 <skill-dir>/scripts/loop_state.py init \
  --state <state-file> \
  --goal "<observable success condition>" \
  --evidence "<current fact or artifact>" \
  --budget-unit "<turns|hypotheses|retries|minutes>" \
  --budget-limit <positive-integer> \
  --next-action "<smallest discriminating action>"
```

Add `--allowed-effect` and `--approval-boundary` whenever writes or external
effects are possible. If `python3` is unavailable, preserve the same five fields
manually and label the run as a non-deterministic fallback.

## Run one bounded cycle

1. Observe from tools or durable evidence.
2. Choose the smallest action that advances or falsifies the approach.
3. Check effect scope; serialize writes unless isolation is proven.
4. Execute and verify. A model's prose claim is not evidence.
5. On apparent success, invoke `$evidence-gate`. Map every observable goal
   clause to typed evidence and require its `check` command to pass.
6. Only then run `finish --status complete --verification
   "<evidence-gate verification value>" --evidence "<result>"`.
7. Otherwise run `advance --evidence "<result>" --next-action "<next check>"`.
   The script emits `budget_exhausted` when the declared ceiling is consumed.
8. Run `show`; continue only while `terminal_status` is `running`.

If later evidence contradicts a recorded fact, use `annotate --evidence
"<correction>"`. Preserve the audit trail; do not reopen or hand-edit terminal
state.

Use `finish` for `blocked`, `needs_human`, `cancelled`, or
`continue_scheduled`. Never translate those states or `budget_exhausted` into
`complete`.

## Preserve durable context

When the installed `worklog` protocol is available, hydrate resume context
before initialization and checkpoint verified state at compaction, delegation,
retry exhaustion, scheduled handoff, or termination. Before cold delegation,
pass the returned `context <slug> --for=compact` pack directly; do not pass the
parent transcript or imply that `spawn` enriches the pack.

For brittle state classification or handoff sequencing, read
[references/examples.md](references/examples.md). Otherwise stay zero-shot.
