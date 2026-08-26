---
name: example-led-instructions
description: Design compact examples for brittle reusable agent instructions. Use when writing or reviewing skills, rubrics, schemas, tool-use instructions, strict output contracts, or prompts where format/style is underspecified or recurrently wrong. Also use when another skill invokes `$example-led-instructions`.
---

# example-led-instructions

Use examples only when they buy reliability.

## Opt-in Preamble

Skill authors: add this line to your SKILL.md to signal that the skill benefits from example-led review:

`For brittle outputs, invoke $example-led-instructions: 0/1/few-shot gate, max 1-3 examples, skip if obvious.`

Agents: when you see this line or are asked to apply the skill, run the gate below and return the output contract.

## Gate

Choose shot count by failure mode, not by preference:

- **Zero-shot:** prose is enough. Use when the format is standard (JSON, markdown, natural language), the task has no known failure mode, or examples would cost more context than they save. *Example: "Summarize this document in 3 sentences" — no example needed.*
- **One-shot:** one compact example resolves a narrow format/style ambiguity. Use when agents recurrently produce the wrong shape, delimiter, or field order. *Example: a skill that requires `key=value` pairs but agents keep producing `key: value`.*
- **Few-shot:** 2-3 examples for strict schemas, brittle tool sequencing, boundary-heavy classification, or repeated failure modes. Use when one example cannot cover the variance. *Example: a classifier with 3+ categories that agents confuse.*

## Example Rules

- Keep examples smaller than the rule they clarify (≤5 lines for input:output, ≤15 lines for INPUT/OUTPUT blocks).
- Prefer `input: output` for short examples (single line or short phrase); use `INPUT` / `OUTPUT` blocks for longer examples (multi-line, structured data).
- Make each example cover a distinct case. Do not repeat near-duplicates.
- Include a negative or contrast example only when it prevents a known recurring error.
- Do not let examples override explicit policy, repo instructions, or user scope.

## Workflow

1. **Identify the brittle output:** What format, schema, or behavior has failed or is likely to fail?
2. **Apply the gate:** Choose zero/one/few-shot based on the failure mode (see Gate section).
3. **Draft examples:** Follow the Example Rules. Keep them minimal.
4. **Fill the output contract:** Return the structured assessment below.
5. **Integrate:** If reviewing, suggest where the examples should live in the target skill. If writing, add them.

## Output Contract

Return this when designing or reviewing an instruction:

```text
shot_count: zero | one | few
format: none | input:output | INPUT/OUTPUT
examples_or_skip_reason: <1-3 compact examples, or why examples are unnecessary>
risk_check: <context cost | overfit/similarity | superficial pattern risk>
acceptance_test: <small prompt or fixture that should now succeed>
```

**Example (filled-in):**

```text
shot_count: one
format: input:output
examples_or_skip_reason:
  - "list files: foo.txt, bar.txt"
  - "list files (empty dir): (no output)"
risk_check: low context cost; no overfit risk (single narrow format)
acceptance_test: prompt "list files in empty dir" produces "(no output)" not "[]"
```
