---
name: which-model
description: Choose the best-value model lane for a task by comparing capability, cost, context window, modality, latency, tool fit, and data policy. Use when the user invokes `/which-model`, asks which model to use, asks for value-for-token model suggestions, or wants session-level model-selection guidelines. `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions.
---

# which-model

Choose by capability and cost for the job, not provider reputation. Treat OpenAI, Anthropic, Chinese models, and local/open-weight routes as first-class candidates.

## Route first

- No arguments: print `## Guideline` and `## Data policy gate`, then stop. Do not read references or fetch live pricing.
- Task prose/capability: apply the data gate, read `references/routing.md`, and return 1-3 suggestions.
- Exact model, availability, current/latest/live, pricing, billing, environment, provider, or harness request: also read `references/catalog.md` and run `bin/model-catalog` as directed there.

Do not preload references that the selected route does not require.

## Task requests

For a non-trivial task, use an available sequential-thinking MCP first to decompose capability requirements, constraints, and risk gates. In Claude-style namespaces this is typically `mcp__sequential-thinking__sequentialthinking`; other agents use their equivalent. Use the result to choose models without exposing chain-of-thought. Skip it for obvious one-lane asks.

Return up to three recommendations: best value, fallback, then premium/escalation only when useful.

```markdown
1. <model or lane> — <why it is best value for this task>
   Use for: <specific subtask shape>
   Avoid if: <capability/privacy/cost caveat>
   Availability: <selectable here | requires wrapper | not available in this harness>
```

Include exact prices only after reading `references/catalog.md` and obtaining a fresh enough snapshot. Otherwise compare qualitatively and label dated calibration as approximate.

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
