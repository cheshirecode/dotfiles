# Task routing reference

Read this file for `/which-model <task prose or capability>`. Apply the root availability gate first. Read `catalog.md` as well only when the request needs exact/current model or harness information.

## Routing heuristics

### 0. Lane definitions by harness

Read only the subsection for the harness in play. Lanes are not portable between
harnesses: the model ids differ, and so does whether a route can actually be
selected.

#### Codex

Read the current delegate tool's model list and select a model it accepts.
For a bounded read-only sweep, use the cheapest capable available lane; keep
dependent decisions, shared writes, and final verification with the lead.
The Codex catalog is seed-only, so its IDs, prices, and availability do not
establish what this session can dispatch. If `spawn_agent` exposes `model`, pass
the selected ID there; on hosts where a full-history fork inherits the parent
model, use a fresh or partial-history brief for an override. Follow the exposed
tool schema, and report when selection is unavailable. A delegate model choice
does not change the parent session's model or grant file isolation.

#### OpenCode

These lanes are **verified against the current opencode catalog** (`~/.cache/which-model/catalog.opencode.json`). Use them when the user is in an opencode session. Each entry maps to a model ID the user can paste into `opencode.json`'s `model` or `small_model` field.

| Lane | Primary model IDs (opencode) | Budget tier | Capability profile | When to pick |
|---|---|---|---|---|
| **frontier synthesis** | `openrouter/gemini-3.1-pro`, `openrouter/~anthropic/claude-opus-latest`, `openrouter/meta/muse-spark-1.3`, `openrouter/kimi-k3` | 🔴 Premium — spend only when justified | highest reasoning, long-context, planning | conflict resolution, multi-agent vote tallying, architectural design docs, final product judgment |
| **strong coding** | `openrouter/kimi-k3`, `openrouter/qwen/qwen3-coder-plus`, `openrouter/z-ai/glm-5.2`, `openrouter/xiaomi/mimo-v2.5-pro` | 🟡 Mid — ok for multi-file work | routine_coding + planning, strong repo-pattern following | multi-file refactors, ambiguous spec interpretation, writing tests from scratch, large-feature implementation |
| **mid-tier generalist** | `openrouter/~anthropic/claude-sonnet-latest`, `openrouter/google/gemini-2.5-pro`, `openrouter/openai/gpt-latest` | 🟡 Mid — safe default | broad capabilities, good tool-use | anything between cheap search and frontier synthesis; safe default when task shape is unclear |
| **cheap code patch** | `openrouter/deepseek/deepseek-v4.1-flash`, `openrouter/qwen/qwen3.6-flash`, `openrouter/qwen/qwen3-coder-flash`, `openrouter/gemini-3.5-flash`, `openrouter/deepseek-v4-flash` | 🟢 Cheap — default for edits | routine_coding only, fast output | targeted patches, test writes, single-file changes under ~50 LOC, re-runnable fixes where retry cost < wait time |
| **parallel voter / mechanical search** | `openrouter/~anthropic/claude-haiku-latest`, `openrouter/gemini-flash-latest`, `openrouter/qwen/qwen3.5-flash-02-23`, `openrouter/poolside/laguna-xs-2.1:free` | 🟢 Cheap — bulk work goes here | mechanical_search or cheap_parallel_voter only | bulk grep-heavy search, classification, extraction, council voting (3+ voters), status checks, inventory sweeps |
| **visual / multimodal** | `openrouter/~anthropic/claude-opus-latest`, `openrouter/google/gemini-2.5-pro`, `openrouter/qwen/qwen3-vl-235b-a22b-instruct` | 🟡 Mid (image input not catalog-tagged) | known multimodal (image input) from provider docs | UI screenshots, Figma analysis, rendered-state inspection, accessibility review of visual elements |

#### Claude Code

Verified 2026-09-09 against `bin/model-catalog --env claude` (21 records; the
ranking column is that helper's `recommendations`, not a guess).

| Lane | Delegation alias | Catalog top pick | When to pick |
|---|---|---|---|
| **mechanical search / parallel voter** | `haiku` | `claude-haiku-4-5` | bulk grep, classification, extraction, status sweeps, 3+ council voters |
| **routine coding** | `sonnet` | `claude-sonnet-5` | targeted patches, single- and multi-file edits, tests from a clear spec |
| **planning / final synthesis** | `fable`, else `opus` | `claude-fable-5-1`, `claude-opus-5` | decomposition, conflict resolution, design docs, cross-context judgment |
| **visual / multimodal** | `fable`, `opus`, `sonnet` | `claude-fable-5-1` | screenshots, rendered state, Figma, visual accessibility |

Two picker facts that are not model choices and are often mistaken for them:

- **Fast mode** (`/fast`) makes Claude Opus emit faster. It is not a downgrade
  to a smaller model, so never present it as a cheap lane.
- The catalog carries **active models with no delegation alias** —
  `claude-mythos-5` and `claude-mythos-5-1` are `requires_program_enrollment`.
  They are legitimate answers to "which model exists" and never to "what should
  this subagent run"; nothing can select them for a delegate.

Deprecated ids (`claude-opus-4-0`, `claude-opus-4-1`, `claude-sonnet-4-0`,
`claude-3-haiku-20240307`) stay `selectable_if_configured` and must still not be
recommended; retired ids cannot be served at all.

#### Cursor

Cursor's catalog is **machine-local**: the helper reads the editor's own
`state.vscdb` (`availableDefaultModels2` in globalStorage) rather than any
public API, so what it can tell you depends on whether Cursor is installed
where the skill is running.

Check which of the two you got before naming anything:

```bash
bin/model-catalog --env cursor --refresh-if-stale \
  | jq '{sources: .catalog.sources, ids: [.catalog.models[].id]}'
```

- A **real** read lists ids from the editor's own model list.
- The **fallback** is a single `cursor-default-fast` record with
  `confidence: "seeded"` and `availability: "unverified_in_harness"`, and
  `sources[]` carries `{"kind": "cursor-state-db", "error": "Cursor state.vscdb
  not found in default locations"}`. Measured on this machine 2026-09-09: the
  fallback, because no Cursor install is present.

**On the fallback, recommend lanes and never exact Cursor model ids.** The seed
carries one placeholder id, no prices, and no context window; presenting it as
a model is inventing availability. Cursor also gates models by plan and
workspace, so even a real local read proves what *this* install offers, not
what the user's teammate or CI sees — say which of those you checked.

Model choice in Cursor is a **picker** decision. Unless the session exposes a
delegation surface of its own, treat any routing advice here as advisory and
say so; do not describe it in the enforceable terms that apply to Claude Code
dispatch above.

### Claude Code delegation model selection

Distinct from the picker: the picker sets what *this* session runs, delegation
sets what a *subagent* runs. In Claude Code this is **enforceable**, not
advisory — say so, because the skill's default caveat is the opposite.

Precedence, strongest first:

1. the `model` argument on the dispatch call — one of `sonnet`, `opus`,
   `haiku`, `fable`
2. the agent definition's `model:` frontmatter (`.claude/agents/*.md`, or the
   SDK `agents` map)
3. a configured default subagent model
4. otherwise the delegate inherits the parent's model

**An alias names a family, not a version.** `opus` selects the harness's current
Opus, which is why a recommendation may name `claude-opus-5` for reasoning but
must be *passed* as `opus`. Never promise an exact id through an alias, and
never pass a catalog id where an alias is expected — it is not in the accepted
set and the dispatch is rejected.

Two exceptions worth knowing before routing a lane to a delegate:

- **A fork inherits the parent model and ignores a `model` override.** Routing a
  cheap lane to a fork silently buys nothing; if the point was to spend less,
  use a fresh agent type instead.
- **Tool access is fixed per agent type and is a routing constraint of its own.**
  A read-only explorer cannot run a lane that needs to edit, however well the
  model fits — filter on tools before comparing models.

### 1. Task-type routing rules

- **Mechanical search, inventory, or status:** cheapest reliable model with tool access. Prefer parallel-voter lanes above. If the search needs semantic understanding beyond keyword matching, use mid-tier generalist instead.
- **Routine coding or targeted patching:** pick from strong-coding or cheap-code lanes available in this harness. Under ~50 LOC → cheap-code lane. Over 50 LOC, ambiguous spec, or multi-file → strong-coding lane.
- **Long-context review (>100k input tokens):** prefer an available frontier synthesis lane with a verified context window large enough for the material. Compare cost only when current pricing is known.
- **Voting or adversarial review (council):** use 3 voters on cheap parallel-voter lanes by default. For high-stakes decisions, escalate one voter to mid-tier generalist while keeping others on cheap lanes. Five voters only when the decision is genuinely close and the budget allows it.
- **Visual or design judgment:** require models with `image_input` capability. The visual model owns the screenshot inspection; supporting search (file lookup, codegrep) runs on a text-only cheap model to save budget.
- **Accessibility review:** split the work. A visual model inspects rendered state/screenshots. A separate text/code model does keyboard flow, focus order, ARIA structure, contrast math, and screen-reader semantics from source.
- **Final synthesis or conflict resolution:** strongest available frontier synthesis lane. Only one model — don't delegate this. It must hold the entire thread.
- **Planning / architecture design:** frontier synthesis or strong-coding lane. Requires reasoning over multiple files and system-level understanding, not just pattern-matching.

### 2. Selection discipline

- Filter first by modality, context, tools, and selectability, plus any constraint the user stated; compare price only among viable routes. Do not add a constraint the user did not state.
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
   Avoid if: <capability/cost/latency caveat>
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

If filtering by hard requirements (modality, context, tools, selectability, plus any constraint the user stated) leaves zero candidates, say so explicitly and recommend the closest relaxable constraint rather than inventing a match.

Include exact prices only after reading `references/catalog.md` and obtaining a fresh enough snapshot. Otherwise compare qualitatively and label dated calibration as approximate.
