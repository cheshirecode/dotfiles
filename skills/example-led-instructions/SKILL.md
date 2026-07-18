---
name: example-led-instructions
description: Design compact examples for brittle reusable agent instructions. Use when writing or reviewing skills, rubrics, schemas, tool-use instructions, strict output contracts, or prompts where format/style is underspecified or recurrently wrong. Also use when another skill invokes `$example-led-instructions`.
---

# example-led-instructions

Use examples only when they buy reliability.

## Opt-in Preamble

Copy or reference this single line from other skills:

`For brittle outputs, invoke $example-led-instructions: 0/1/few-shot gate, max 1-3 examples, skip if obvious.`

## Gate

- **Zero-shot:** task is obvious, prose instructions are enough, or examples would cost more context than they save.
- **One-shot:** one compact example resolves a narrow format/style ambiguity.
- **Few-shot:** use 2-3 examples only for strict schemas, brittle tool sequencing, boundary-heavy classification, or repeated failure modes.

## Example Rules

- Keep examples smaller than the rule they clarify.
- Prefer `input: output` for short examples; use `INPUT` / `OUTPUT` blocks for longer examples.
- Make each example cover a distinct case. Do not repeat near-duplicates.
- Include a negative or contrast example only when it prevents a known recurring error.
- Do not let examples override explicit policy, repo instructions, or user scope.

## Output Contract

Return this when designing or reviewing an instruction:

```text
shot_count: zero | one | few
format: none | input:output | INPUT/OUTPUT
examples_or_skip_reason: <1-3 compact examples, or why examples are unnecessary>
risk_check: <context cost | overfit/similarity | superficial pattern risk>
acceptance_test: <small prompt or fixture that should now succeed>
```
