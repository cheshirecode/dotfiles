---
name: loop-helpers
description: "Optional deterministic helpers for loop-engineering context packs and fail-open Caveman transport decisions. Use when a bounded loop needs a compact handoff or an explicit shrink/Pixel/convert gate; do not use for ordinary one-shot output or to install/configure Caveman."
---

# loop-helpers

Use these helpers only when the loop trigger is true. They emit a compact
decision or pack; they do not execute a provider proxy, install Caveman, read a
parent transcript, or rewrite a canonical skill.

## Resolve the skill directory

Use this file's load directory as `<skill-dir>`. Only if unavailable, read
[resolver.md](references/resolver.md). If the optional payload is absent, record
`context-pack: skipped — not installed` or `transport-gate: skipped — not installed`.
Do not guess paths or install anything.

## Compact context pack

Build a five-field handoff from explicit inputs and keep raw evidence in
`/tmp`, `$TMPDIR`, or CCR:

```bash
python3 <skill-dir>/scripts/context_pack.py \
  --objective "<goal>" \
  --known-evidence "<typed reference>" \
  --constraints "<effect boundary>" \
  --budget "<remaining budget>" \
  --requested-return "<evidence and next action>" \
  --recovery-handle "<optional handle>"
```

The script prints one compact JSON object. Pass that object to a delegate or
write it to a system temporary file; never append the parent transcript.

## Transport gate

Only for a shrink, convert, or pixel decision, read
[transport.md](references/transport.md). It owns flags, allowlist requirements,
and fail-open semantics. Do not read it for context-pack requests.

Return the helper result or its artifact path concisely. Formatting a result
does not require loading another skill.
