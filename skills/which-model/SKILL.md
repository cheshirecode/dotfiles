---
name: which-model
description: Choose the best-value model lane for a task by comparing capability, cost, context window, modality, latency, tool fit, and data policy. Use when the user invokes `/which-model`, asks which model to use, asks for value-for-token model suggestions, or wants session-level model-selection guidelines. `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions.
---

# which-model

Choose by capability and cost for the job, not provider reputation. Treat OpenAI, Anthropic, Chinese models, and local/open-weight routes as first-class candidates.

Skip optional delegation routing if no delegate surface exists or in-band work is sufficient. Explicit model-advice requests still follow the routes below.

## Resolve the skill directory

Flattening installers separate this file from its payload. Resolve the root once:

```bash
SKILL_ROOT=""
for d in "$HOME/.claude/which-model" \
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
If missing, print the guideline and data gate, report the missing payload, and
suggest restarting the installer or cloning super-ruler. Do not invent prices,
context windows, or model IDs for routes requiring the catalog.

## Route first

- No arguments: print `## Guideline` and `## Data policy gate`, then stop. Do not read references or fetch live pricing.
- Task prose/capability: apply the data gate, read `references/routing.md`, and return 1-3 suggestions.
- Exact model, availability, current/latest/live, pricing, billing, environment, provider, or harness request: also read `references/catalog.md` and run `bin/model-catalog` as directed there.
- Comparison request ("X vs Y", "which is cheaper"): read `references/catalog.md`, run `bin/model-catalog` for the relevant env, and return a side-by-side with prices, context, and capability differences.
- Unknown or unrecognized argument: print usage (`/which-model` or `/which-model <task description>`) and stop.

Do not preload references that the selected route does not require.

## Guideline

1. Identify the job: mechanical search, code edit, long-context review, visual judgment, adversarial verification, planning, synthesis, or final decision.
2. Filter by hard requirements: data policy, tool access, modality, context window, latency, structured-output reliability, and actual selectability in the current harness.
3. Compare remaining candidates by capability per dollar on the specific job.
4. Spend cheap tokens on search angles, negative evidence, fixture checks, and compact proofs—not longer prose.
5. Reserve frontier/premium tokens for cross-context synthesis, high-risk judgment, needed visual/design calls, and contradictory evidence.

## Data policy gate

Do not route secrets, customer data, unreleased strategy, or private proprietary code through an unapproved provider because it is cheap. Approval must be explicit enough to cite: allowed data class, provider/route, retention/training terms, and whether the current harness can enforce the route. If approval cannot be verified, recommend local, self-hosted, approved first-party, or explicitly approved open-weight routes.

## Output rules

- Return at most three suggestions.
- Prefer lanes when exact availability is unknown: `cheap long-context code model`, `mid multimodal model`, or `frontier synthesis model`.
- State when the current harness cannot actually select a recommendation.
- Tie the rationale to task capability, cost, and caveat in one line.
- Summarize decision factors only; do not print private chain-of-thought.

## Hook automation (offer, never configure silently)

No hook sets a session model; `SessionStart` only injects context. A
`PreToolUse` hook matching `Agent|Task` does set a sub-agent model: it
returns `hookSpecificOutput.updatedInput` carrying `model`.

Tell the user this hook exists when they delegate, and ask before editing
settings. Echo the whole input object or the harness discards it. Skip
`subagent_type: "fork"`; it ignores `model`.
