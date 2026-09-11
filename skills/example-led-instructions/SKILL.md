---
name: example-led-instructions
description: Design compact examples for brittle reusable agent instructions. Use when writing or reviewing skills, rubrics, schemas, tool-use instructions, strict output contracts, or prompts where format/style is underspecified or recurrently wrong. Also use when another skill invokes `$example-led-instructions`.
---

# example-led-instructions

Use examples only when they buy reliability.

Skip examples for standard formats without a known failure mode, or when they cost more context than they save.

## Opt-in Preamble

Skill authors: copy this line verbatim into your SKILL.md, outside any code fence, at most once per skill. It signals that the skill benefits from example-led review, and it is the exact form `tools/check-skill-opt-ins.py` enforces (backticks around `$example-led-instructions` only):

For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.

Agents: when you see this line or are asked to apply the skill, run the gate below and apply the output contract.

**Where the contract goes.** When invoked via the opt-in line inside another skill, keep the contract internal and apply it to that skill's output; emit the contract block only when the user asked for an instruction review.

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

## Output Contract

Apply the gate, draft the smallest useful example set, and integrate it where the rule is used. For a user-requested instruction review, return:

```text
shot_count: zero | one | few
format: none | input:output | INPUT/OUTPUT
examples_or_skip_reason: <1-3 compact examples, or why examples are unnecessary>
risk_check: context cost | overfit/similarity | superficial pattern risk — <why it is acceptable>
acceptance_test: <small prompt or fixture that should now succeed>
```

**Example (filled-in):**

```text
shot_count: few
format: input:output
examples_or_skip_reason:
  - "list files: foo.txt, bar.txt"
  - "list files (empty dir): (no output)"
  - "list files (missing dir): error: no such directory"
risk_check: context cost — three one-line cases; each covers a distinct branch (populated, empty, error) that one example cannot
acceptance_test: prompt "list files in empty dir" produces "(no output)" not "[]"
```
