---
name: loop-helpers
description: "Optional deterministic helpers for loop-engineering context packs and fail-open Caveman transport decisions. Use when a bounded loop needs a compact handoff or an explicit shrink/Pixel/convert gate; do not use for ordinary one-shot output or to install/configure Caveman."
---

# loop-helpers

Use these helpers only when the loop trigger is true. They emit a compact
decision or pack; they do not execute a provider proxy, install Caveman, read a
parent transcript, or rewrite a canonical skill.

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. If uncertain,
search for `context_pack.py` under the skill roots.
`loop-engineering/references/resolvers.md` owns this resolver pattern, including the per-host variants and the fixture that executes them; the line below is the same pattern with this skill's own sentinel file.

```bash
# Roots checked in order; empty when absent — never a bogus "./..":
SKILL_DIR="$(for r in ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills; do f=$(find -L "$r" -name context_pack.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
```

This skill is `optional: true`, so it is often absent. When `$SKILL_DIR`
resolves empty, do not guess a path — record `transport-gate: skipped — not
installed` (or `context-pack: skipped — not installed`) and continue.

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

The script prints one compact JSON object, capped at 8192 serialized UTF-8 bytes
including its newline. This is a payload bound, not a token estimate. Oversized
packs exit 2 with no stdout and no silently dropped fields. Replace detailed
evidence with artifact references and retry; preserve constraints and recovery
handles. Use `--max-bytes <positive integer>` only when a larger receiving budget
is justified. Pass the object to a delegate or save it to a system temporary
file; never append the parent transcript. Persist referenced evidence in an
authorized durable store before a cross-session handoff.

## Transport gate

Only for a shrink, convert, or pixel decision, read
[transport-gate.md](references/transport-gate.md). It owns this helper's flags
and allowlist requirements; `loop-engineering/references/transport.md` owns the
policy (authorization, candidacy, fail-open). Do not read it for context-pack
requests.

Return the helper result or its artifact path concisely. Formatting a result
does not require loading another skill.
