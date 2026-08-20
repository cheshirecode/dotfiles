---
name: loop-helpers
description: "Optional deterministic helpers for loop-engineering context packs and fail-open Caveman transport decisions. Use when a bounded loop needs a compact handoff or an explicit shrink/Pixel/convert gate; do not use for ordinary one-shot output or to install/configure Caveman."
---

# loop-helpers

Use these helpers only when the loop trigger is true. They emit a compact
decision or pack; they do not execute a provider proxy, install Caveman, read a
parent transcript, or rewrite a canonical skill.

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

Ask the helper for a decision before invoking Caveman. The caller supplies the
facts that cannot be inferred safely from a filename: authorization, measured
win, recovery, producer-status preservation, density, and model legibility.

```bash
python3 <skill-dir>/scripts/transport_gate.py \
  --mode pixel --authorized --measured-win --recoverable \
  --dense --legible --model "<model>"
```

`decision=use` is permission to run the chosen documented command. Any
`decision=skip` keeps the original bytes and records the reason. `pixel` also
requires a configured legible model; `shrink` requires producer-status
preservation; `convert` requires an installed copy. The helper never claims a
token saving is verified: the caller supplies measured evidence.

For readable visible updates, invoke the existing explicit `i-have-adhd` skill
when wanted. Do not duplicate its session-wide output boundary here.
