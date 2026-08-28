---
name: which-model
description: Choose the best-value model lane for a task by comparing capability, cost, context window, modality, latency, tool fit, and data policy. Use when the user invokes `/which-model`, asks which model to use, asks for value-for-token model suggestions, or wants session-level model-selection guidelines. `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions.
---

# which-model

Choose by capability and cost for the job, not provider reputation. Treat OpenAI, Anthropic, Chinese models, and local/open-weight routes as first-class candidates.

## When to use

- User invokes `/which-model`, asks which model to use, or wants value-for-token model suggestions
- Session-level model-selection guidelines are needed
- `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions

Skip if: no delegate surface, or in-band work is sufficient for the task.

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. All script and reference paths below are relative to it:

```bash
# If the skill is in the dotfiles repo:
SKILL_DIR="$HOME/Documents/oss/dotfiles/skills/which-model"
# Or, if loaded by an agent that exposes the skill root:
SKILL_DIR="<the directory the agent loaded this SKILL.md from>"
```

Script invocations use `python3 <skill-dir>/bin/model-catalog`. Reference reads use `<skill-dir>/references/routing.md` and `<skill-dir>/references/catalog.md`.

## Route first

- No arguments: print `## Guideline` and `## Data policy gate`, then stop. Do not read references or fetch live pricing.
- Task prose/capability: apply the data gate, read `references/routing.md`, and return 1-3 suggestions.
- Exact model, availability, current/latest/live, pricing, billing, environment, provider, or harness request: also read `references/catalog.md` and run `bin/model-catalog` as directed there.
- Comparison request ("X vs Y", "which is cheaper"): read `references/catalog.md`, run `bin/model-catalog` for the relevant env, and return a side-by-side with prices, context, and capability differences.
- Unknown or unrecognized argument: print usage (`/which-model` or `/which-model <task description>`) and stop.

Do not preload references that the selected route does not require.

## Task requests

See [references/routing.md](references/routing.md) for the decomposition
procedure and the per-agent sequential-thinking namespaces.
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
