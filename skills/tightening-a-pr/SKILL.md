---
name: tightening-a-pr
description: Compatibility alias for explicit tightening-a-pr invocations. Delegates to pr-review closeout and preserves the legacy output schema.
---
# DEPRECATED: tightening-a-pr delegates to pr-review

This skill is a thin backward-compatibility shim. It has no independent logic.

## Behavior

When invoked:
1. Load `$pr-review` and invoke its **closeout** entry point with the same PR number and worklog slug.
2. Map pr-review's closeout output (distilled → codified → deslop → checkpoint) back to tightening-a-pr's original output schema (`=== distilled learnings ===` → `=== codified ===` → `=== PR deslop (ship-hygiene) ===` → `=== checkpoint ===`).

For new callers, use `$pr-review` closeout directly. Preserve this alias for existing invocations.
