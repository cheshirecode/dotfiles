---
name: which-model
description: Choose the best-value model lane for a task by comparing capability, cost, context window, modality, latency, tool fit, and data policy. Use when the user invokes `/which-model`, asks which model to use, asks for value-for-token model suggestions, or wants session-level model-selection guidelines. `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions.
---

# which-model

Model choice is an engineering tradeoff, not a brand ladder. Treat OpenAI, Anthropic,
Chinese models (DeepSeek, Qwen, GLM/Z.ai, Kimi/Moonshot, MiniMax/MiMo), and local/open-weight
routes as first-class candidates. Pick by capability and cost for the job at hand.

## Command modes

### `/which-model`

Print the guideline below and stop. Use this once near session start when model-routing doctrine
should be loaded into context. Do not fetch live pricing in no-argument mode.

### `/which-model <task prose or capability>`

If the sequential-thinking MCP is available, call it first for non-trivial tasks to decompose the
job into capability requirements, constraints, and risk gates. In Claude-style tool namespaces this
is typically `mcp__sequential-thinking__sequentialthinking`; other agents should use their
equivalent sequential-thinking MCP tool. Use the result to choose models; do not expose
chain-of-thought. Skip this for obvious one-lane asks.

Return up to 1-3 recommendations, ordered best-value first, then fallback, then premium/escalation
only when useful. Keep the answer compact:

```markdown
1. <model or lane> — <why it is best value for this task>
   Use for: <specific subtask shape>
   Avoid if: <capability/privacy/cost caveat>
   Availability: <selectable here | requires wrapper | not available in this harness>
```

Include exact prices only when a fresh pricing snapshot is available or the user asks for current
pricing. Otherwise compare qualitatively and label any dated calibration as approximate.

## Guideline

1. Identify the job: mechanical search, code edit, long-context review, visual judgment,
   adversarial verification, planning, synthesis, or final decision.
2. Filter by hard requirements: data policy, tool access, modality, context window, latency,
   structured-output reliability, and whether the model can actually be selected in the current
   harness.
3. Compare remaining candidates by value for token: capability per dollar on the specific job,
   not provider reputation.
4. Spend cheap tokens to reduce expensive uncertainty: more search angles, negative evidence,
   fixture checks, and compact proofs. Do not spend them on longer prose.
5. Reserve frontier/premium tokens for cross-context synthesis, high-risk judgment, visual/design
   calls when needed, and resolving contradictory evidence.

## Pricing freshness

Price in USD per million input/output tokens. Keep a small snapshot cache:

- `$XDG_CACHE_HOME/model-pricing-snapshot.json`
- fallback `~/.cache/model-pricing-snapshot.json`
- temporary fallback `/tmp/model-pricing-snapshot.json`

Use cached prices for routine routing when `<3 days` old. At `3-5 days`, use cache only for rough
routing; refresh before exact dollar quotes or material billing decisions. Treat `>5 days` as
stale. Always refresh when the user asks for current/latest/live pricing.

Use official provider sources: OpenRouter model API for OpenRouter, official OpenAI pricing docs
or API surfaces for OpenAI, and official Anthropic pricing docs or API surfaces for Claude. For
provider-direct DeepSeek, Qwen, GLM/Z.ai, Kimi/Moonshot, MiniMax/MiMo, or local routes, use that
provider's official pricing/API surface when available; otherwise label prices as unverified.

## Routing heuristics

- **Mechanical search/inventory/status checks**: pick the cheapest reliable model with enough
  context and tool access. DeepSeek/Qwen/MiniMax/MiMo-class lanes are first-class candidates.
- **Routine coding or targeted patching**: pick the cheapest model that reliably follows repo
  patterns and tests. Qwen coder, Kimi/Moonshot code, GLM/Z.ai, OpenAI mid, Anthropic Sonnet-class,
  or local code models can all win depending on harness and repo fit.
- **Long-context review**: prefer models with large context and low input cost, then require
  evidence-shaped output: file refs, commands, pass/fail status, and uncertainty.
- **Voting/adversarial review**: use mid-tier judgment models. Use 3 voters by default; use 5 only
  when the decision is high-impact, close, and cheap enough.
- **Visual/design judgment**: require multimodal capability. Text-only cheap models can support
  surrounding search but cannot own the visual decision.
- **Accessibility review**: separate screenshot judgment from semantic checks. Visual models can
  inspect rendered state, but keyboard flow, focus order, ARIA, contrast math, and screen-reader
  semantics need code inspection and/or deterministic a11y tooling.
- **Final synthesis / conflict resolution**: use the strongest available model holding the whole
  thread when the cost is justified.

## Data policy gate

Do not route secrets, customer data, unreleased strategy, or private proprietary code through an
unapproved provider route just because it is cheap. Approval must be explicit enough to cite:
allowed data class, provider/route, retention/training terms, and whether the current harness can
enforce the route. If approval cannot be verified, recommend local, self-hosted, approved
first-party, or explicitly approved open-weight routes.

## Output rules

- Return at most 3 suggestions.
- Prefer lanes when exact model availability is unknown: "cheap long-context code model",
  "mid multimodal model", "frontier synthesis model".
- State when the current harness cannot actually select a recommended model.
- Give a one-line rationale tied to the task: capability + cost + caveat.
- Summarize reasoning as decision factors only; do not print private chain-of-thought.
