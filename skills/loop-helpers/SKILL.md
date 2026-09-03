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
search for `context_pack.py` under the skill roots:

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
`decision=skip` keeps the original bytes and records the reason. The helper
**always exits 0** in both the use and the skip case: parse `decision=` from
stdout, never gate on exit status.

Each mode has one extra requirement and the flag that satisfies it:

- `shrink` — producer status preserved: `--producer-status-preserved`
- `convert` — an installed copy exists: `--installed-copy`
- `pixel` — a dense, legible payload for a configured model: `--dense
  --legible --model <id>`

`CAVE_PIXEL_MODELS` is the comma-separated allowlist of model ids that read
pixel payloads, and it is a real Caveman variable: the CLI applies it to
`think.pixel.models`. It defaults here to `claude-fable-5,gpt-5.6`; both are
current ids that Caveman's engine recognises, so the defaults are usable as
they stand. Add the ids actually in use rather than replacing them:
`CAVE_PIXEL_MODELS="<id>,<id>"`. An unlisted `--model` returns
`decision=skip reason=model-not-configured hint=set-CAVE_PIXEL_MODELS`.

**`decision=use` is not sufficient on its own.** Caveman ships pixel *off*:
`think.pixel.models` is `[]` by default, and an empty list passes no allowlist
to the proxy at all. This gate answers "should we attempt pixel", using its own
list; Caveman must be configured separately or it will not pixel whatever this
returns. `caveman tools config set` also accepts an unknown model id without
complaint, so a typo there is caught by nothing — this gate's `skip` is the
only place a wrong id is reported.

Verified 2026-09-03 against `@caveman-ai/cli` 1.3.1 / binaries `bin-v1.1.4`:
`caveman-engine pixel simulate --model` gives `claude-fable-5` and `gpt-5.6`
their own pixel geometry, while an unknown id, a bogus id and an empty id all
collapse to one identical fallback — which is what makes the first two
*recognised* rather than merely accepted.

The helper never claims a token saving is verified: the caller supplies
measured evidence.

For readable visible updates, follow the "Compaction-friendly output" section
of the `loop-engineering` skill. Do not duplicate its output boundary here.
