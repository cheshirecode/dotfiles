---
name: which-model
description: Choose model lanes by task capability, cost, context, modality, latency, tools, and harness availability. Use for /which-model, model recommendations, value-for-token comparisons, or session model-selection guidance.
---

# which-model

Choose by capability and cost for the job, not provider reputation. OpenAI, Anthropic, Chinese, and local/open-weight routes are all first-class candidates.

Skip optional delegation routing when no delegate surface exists or in-band work suffices. Explicit model-advice requests still follow the routes below.

## Resolve the skill directory

Use this file's load directory as `$SKILL_ROOT` when it contains `bin/model-catalog`. Only if the load path is unknown or a flattening installer separated the payload, run this fallback:

```bash
SKILL_ROOT=""
for d in "$PWD/skills/which-model" \
         "$HOME/.agents/skills/which-model" \
         "$HOME/.codex/skills/which-model" \
         "$HOME/.claude/which-model" \
         "$HOME/.claude/skills/which-model" \
         "${SUPER_RULER:-$HOME/.super-ruler}/.ruler/skills/which-model" \
         "/workspace/super-ruler/.ruler/skills/which-model" \
         "$HOME/super-ruler/.ruler/skills/which-model" \
         "$PWD/.claude/skills/which-model" \
         "$PWD"; do
  if [ -x "$d/bin/model-catalog" ]; then SKILL_ROOT="$d"; break; fi
done
echo "${SKILL_ROOT:-not found}"
```

Resolve every `bin/…` and `references/…` path below under `$SKILL_ROOT`.
If missing, print the guideline and availability gate, say the payload is
missing, and do not recall prices, context windows, or model IDs from memory.

## Route first

- No arguments: print `## Guideline` and `## Availability gate`, then stop. Do not read references or fetch live pricing.
- Task prose/capability: apply the availability gate, read `references/routing.md`, and return 1-3 suggestions.
- Exact model, availability, pricing, billing, environment, provider, or harness request: also read `references/catalog.md` and run `bin/model-catalog` as directed there.
- Comparison ("X vs Y", "which is cheaper"): read `references/catalog.md`, run `bin/model-catalog` for the env, and return a side-by-side of price, context, and capability.
- Unrecognized argument: print usage and stop.

Do not preload references that the selected route does not require.

## Guideline

1. Identify the job: mechanical search, code edit, long-context review, visual judgment, adversarial verification, planning, synthesis, or final decision.
2. Filter by hard requirements: tool access, modality, context window, latency, structured-output reliability, selectability here, and any constraint the user stated.
3. Compare remaining candidates by capability per dollar on the specific job.
4. Spend cheap tokens on search angles, negative evidence, fixture checks, and compact proofs—not longer prose.
5. Reserve frontier tokens for cross-context synthesis, high-risk judgment, visual/design calls, and contradictory evidence.

## Availability gate

The candidate set is what this harness can select with the credentials it has. Read it from the harness's model list or `bin/model-catalog`; never assume it. When the intended lane names a model this harness cannot select, map the intent to an available one and say which lane it stood in for.

Do not invent a restriction the user did not state. Approved providers, and whether data may leave this machine, are the user's calls; absent one, route on capability, cost, and availability alone. A missing approval is not a refusal reason. When the user states a constraint, filter on it and name it in the recommendation.

## Output rules

- Return at most three suggestions.
- Prefer lanes when exact availability is unknown: `cheap long-context code model`, `mid multimodal model`, or `frontier synthesis model`.
- State when this harness cannot select a recommendation.
- Tie the rationale to task capability, cost, and caveat in one line.
- Summarize decision factors; do not print private chain-of-thought.

## Hook automation

No hook sets a session model; `SessionStart` only injects context. A
`PreToolUse` hook matching `Agent|Task` does set a sub-agent model: it
returns `hookSpecificOutput.updatedInput` carrying `model`.

Tell the user this hook exists when they delegate, and ask before editing
settings. Echo the whole input object or the harness discards it. Skip
`subagent_type: "fork"`; it ignores `model`.
