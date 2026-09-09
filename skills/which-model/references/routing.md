# Task routing reference

Read this file for `/which-model <task prose or capability>`. Apply the root data-policy gate first. Read `catalog.md` as well only when the request needs exact/current model or harness information.

## Routing heuristics

### 0. Lane definitions by harness

Read only the subsection for the harness in play. Lanes are not portable between
harnesses: the model ids differ, and so does whether a route can actually be
selected.

#### OpenCode

These lanes are **verified against the current opencode catalog** (`~/.cache/which-model/catalog.opencode.json`). Use them when the user is in an opencode session. Each entry maps to a model ID the user can paste into `opencode.json`'s `model` or `small_model` field.

| Lane | Primary model IDs (opencode) | Budget tier | Capability profile | When to pick |
|---|---|---|---|---|
| **frontier synthesis** | `openrouter/gemini-3.1-pro`, `openrouter/~anthropic/claude-opus-latest`, `openrouter/kimi-k3` | 🔴 Premium — spend only when justified | highest reasoning, long-context, planning | conflict resolution, multi-agent vote tallying, architectural design docs, final product judgment |
| **strong coding** | `openrouter/kimi-k3`, `openrouter/qwen/qwen3-coder-plus`, `openrouter/z-ai/glm-5.2`, `openrouter/xiaomi/mimo-v2.5-pro` | 🟡 Mid — ok for multi-file work | routine_coding + planning, strong repo-pattern following | multi-file refactors, ambiguous spec interpretation, writing tests from scratch, large-feature implementation |
| **mid-tier generalist** | `openrouter/~anthropic/claude-sonnet-latest`, `openrouter/google/gemini-2.5-pro`, `openrouter/openai/gpt-latest` | 🟡 Mid — safe default | broad capabilities, good tool-use | anything between cheap search and frontier synthesis; safe default when task shape is unclear |
| **cheap code patch** | `openrouter/qwen/qwen3.6-flash`, `openrouter/qwen/qwen3-coder-flash`, `openrouter/gemini-3.5-flash`, `openrouter/deepseek-v4-flash` | 🟢 Cheap — default for edits | routine_coding only, fast output | targeted patches, test writes, single-file changes under ~50 LOC, re-runnable fixes where retry cost < wait time |
| **parallel voter / mechanical search** | `openrouter/~anthropic/claude-haiku-latest`, `openrouter/gemini-flash-latest`, `openrouter/qwen/qwen3.5-flash-02-23`, `openrouter/poolside/laguna-xs-2.1:free` | 🟢 Cheap — bulk work goes here | mechanical_search or cheap_parallel_voter only | bulk grep-heavy search, classification, extraction, council voting (3+ voters), status checks, inventory sweeps |
| **visual / multimodal** | `openrouter/~anthropic/claude-opus-latest`, `openrouter/google/gemini-2.5-pro`, `openrouter/qwen/qwen3-vl-235b-a22b-instruct` | 🟡 Mid (image input not catalog-tagged) | known multimodal (image input) from provider docs | UI screenshots, Figma analysis, rendered-state inspection, accessibility review of visual elements |

### 1. Task-type routing rules

- **Mechanical search, inventory, or status:** cheapest reliable model with tool access. Prefer parallel-voter lanes above. If the search needs semantic understanding beyond keyword matching, use mid-tier generalist instead.
- **Routine coding or targeted patching:** pick from strong-coding or cheap-code lanes depending on change scope. Under ~50 LOC → cheap-code lane. Over 50 LOC, ambiguous spec, or multi-file → strong-coding lane. `kimi-k3` wins at scale (long context + reasoning); `qwen3-coder-plus` and `glm-5.2` are close substitutes when kimi is unavailable or too slow.
- **Long-context review (>100k input tokens):** prefer frontier synthesis lanes — gemini-3.1-pro has the largest proven context window and handles document review well. claude-opus-latest also works but may be pricier if billing applies.
- **Voting or adversarial review (council):** use 3 voters on cheap parallel-voter lanes by default. For high-stakes decisions, escalate one voter to mid-tier generalist while keeping others on cheap lanes. Five voters only when the decision is genuinely close and the budget allows it.
- **Visual or design judgment:** require models with `image_input` capability. The visual model owns the screenshot inspection; supporting search (file lookup, codegrep) runs on a text-only cheap model to save budget.
- **Accessibility review:** split the work. A visual model inspects rendered state/screenshots. A separate text/code model does keyboard flow, focus order, ARIA structure, contrast math, and screen-reader semantics from source.
- **Final synthesis or conflict resolution:** strongest available frontier synthesis lane. Only one model — don't delegate this. It must hold the entire thread.
- **Planning / architecture design:** frontier synthesis or strong-coding lane. Requires reasoning over multiple files and system-level understanding, not just pattern-matching.

### 0a. Budget guardrails (2-3 month, ~$50 total)

The default orchestrator model runs on flash-tier prices (`gemini-flash-latest` / `qwen3.7-plus`). Only escalate when the lane justification applies:

- **Always cheap**: mechanical search, inventory sweeps, single-file edits <50 LOC, formatting, grep-heavy audits, CI summary generation. Route to parallel-voter or cheap-code lanes without asking.
- **Escalate only when justified**: multi-file refactors (>50 LOC), ambiguous spec interpretation, architectural planning, conflict resolution between agents. These warrant mid-tier or frontier; everything else stays cheap.
- **Frontier reservation**: use `gemini-3.1-pro`, `claude-opus-latest`, or `kimi-k3` only for final synthesis, council vote tallying, design docs that will be committed, or when two sub-agents contradict and you need the strongest resolver. If the task can be solved by composing cheap + mid work, do that instead.
- **Visual delegation, not ownership**: the orchestrator never inspects images itself unless the user shows one inline. For screenshot/Figma work, delegate to the `frontend` subagent which gets its own model selection. The visual lane in routing.md is for direct model selection, not orchestration-level image inspection.
- **Never escalate preemptively**. If a cheap or mid tier produces a plausible first pass, let the orchestrator verify before escalating. Escalation costs are real — they compound across sub-agents and council voters.

### 2. Selection discipline

- Filter first by policy, modality, context, tools, and selectability; compare price only among viable routes.
- State whether routing is enforceable in the current harness or merely advisory.
- Use cheap lanes for bounded mechanical work and mid-tier lanes for judgment. Escalate only the unresolved synthesis or high-risk decision.
- Prefer a lane over an exact model when availability has not been verified through `catalog.md`.
- When the user provides exact model names that don't exist in the opencode catalog (e.g., `openrouter/fake-model-that-does-not-exist`), verify against the running `bin/model-catalog --env opencode --refresh-if-stale` call and recommend the closest available alternative.

## Task requests

For a non-trivial task, use an available sequential-thinking MCP first to decompose capability requirements, constraints, and risk gates. Common namespace mappings:
- Claude Code: `mcp__sequential-thinking__sequentialthinking`
- OpenCode: check available MCPs for a structured-decomposition or thinking tool
- Other agents: use their equivalent structured-reasoning tool, or decompose inline

Use the result to choose models without exposing chain-of-thought. Skip it for obvious one-lane asks.

Return up to three recommendations: best value, fallback, then premium/escalation only when useful.

```markdown
1. <model or lane> — <why it is best value for this task>
   Use for: <specific subtask shape>
   Avoid if: <capability/privacy/cost caveat>
   Availability: <selectable here | requires wrapper | not available in this harness>
```

Concrete example:

```markdown
1. openrouter/kimi-k3 — best value for multi-file refactor in opencode: long context, planning tags, strong routine_coding rating
   Use for: changes touching 3+ files, ambiguous spec requiring inference, feature implementation >50 LOC
   Avoid if: task is a single-file grep-and-fix under 20 lines; use a flash lane instead
   Availability: selectable here (openrouter)
2. openrouter/qwen/qwen3.6-flash — fallback when kimi is congested or latency matters more than quality
   Use for: targeted patches, test writes, quick fixes where retry cost is low
   Avoid if: task requires reasoning about system architecture or cross-module implications
   Availability: selectable here (openrouter)
```

If filtering by hard requirements (data policy, modality, context, tools) leaves zero candidates, say so explicitly and recommend the closest relaxable constraint rather than inventing a match.

Include exact prices only after reading `references/catalog.md` and obtaining a fresh enough snapshot. Otherwise compare qualitatively and label dated calibration as approximate.
