---
name: tightening-a-pr
description: DEPRECATED — use $pr-review instead. Thin shim kept so existing routing keeps working. Loads $pr-review, runs its closeout entry point (steps 1-4), and relabels the output to tightening-a-pr's original schema for consumers that still expect it. Triggers "tighten up PR #N", "wrap up this PR", "distill the learnings from this PR", "deslop this PR before handoff".
---
# DEPRECATED: tightening-a-pr delegates to pr-review

This skill is a thin backward-compatibility shim. It has no independent logic.

## Behavior

When invoked:
1. Load `$pr-review` and invoke its **closeout** entry point with the same PR number and worklog slug.
2. Map pr-review's closeout output (distilled → codified → deslop → checkpoint) back to tightening-a-pr's original output schema (`=== distilled learnings ===` → `=== codified ===` → `=== PR deslop (ship-hygiene) ===` → `=== checkpoint ===`).

## Why this exists

This shim exists only for callers that still name `$tightening-a-pr`.
loop-engineering's routing table no longer does — it routes one owner,
`$pr-review`, which chooses review or closeout from the request. Point any
remaining caller at `$pr-review` and ask it for closeout; there is no
`--tighten` flag in the routing table, because the Owner column holds a
skill name and a flag there breaks the compose-table contract.
