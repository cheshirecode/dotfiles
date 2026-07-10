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

## Model catalog freshness

Cache an environment-specific model catalog, not only prices. "Available" depends on where this
skill is running: Codex/OpenAI, Claude, Cursor, OpenCode, or an unknown harness can expose different
models, tools, routing policies, and billing. `--env` selects the harness/session; optional
`--provider` independently selects the catalog source and defaults to the resolved environment.
Without `--env`, `WHICH_MODEL_ENV` wins; active session markers and process ancestry outrank passive
home/config/credential evidence such as `CODEX_HOME`, cwd config directories, or provider API keys.

Catalog paths:

- omitted provider: `$XDG_CACHE_HOME/which-model/catalog.<env>.json`
- explicit provider: `$XDG_CACHE_HOME/which-model/catalog.<env>.<provider>.json`
- fallback root: `~/.cache/which-model/`
- temporary/test root: `$WHICH_MODEL_CACHE_HOME/`

Use `bin/model-catalog` before recommending exact models:

```bash
skills/which-model/bin/model-catalog --env auto --refresh-if-stale
skills/which-model/bin/model-catalog --env opencode --refresh-if-stale --task routine_coding --top 3
skills/which-model/bin/model-catalog --env opencode --provider openrouter --refresh-if-stale
```

Provider-specific catalog implementation handoff lives in `docs/provider-handover.md`.

Refresh rules:

- Missing cache: build a catalog before answering.
- `<3 days` old: use silently for routine routing.
- `3-5 days` old: use for rough routing; refresh before exact dollar quotes or material billing
  decisions.
- `>5 days` old: refresh first; if refresh fails, use the stale catalog only with a warning.
- Always refresh when the user asks for current/latest/live model availability or pricing.

Catalog records should include model id, provider, availability in the current harness, input/output
price per million tokens when known, context window, max output, capabilities, caveats, confidence,
and normalized `task_fit` tags. Prefer official or harness-native sources that do not require the
skill to hold provider API keys: OpenCode's configured model surface and Models.dev for OpenCode,
OpenAI model docs/API surfaces for Codex/OpenAI, Cursor local `state.vscdb` reactive storage
(`availableDefaultModels2`) for the `cursor` env, and the public OpenRouter models API
(`https://openrouter.ai/api/v1/models`) for `openrouter`. For `claude`, the helper builds from a
dated Anthropic docs snapshot (model IDs enriched with pricing/limits) with no API key and no
network; when live availability matters the running session/agent lists models itself and injects
that JSON via `WHICH_MODEL_CATALOG_SOURCE`—the skill must never hold an Anthropic API key. Label
prices or availability as unverified when the source cannot prove them.

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
