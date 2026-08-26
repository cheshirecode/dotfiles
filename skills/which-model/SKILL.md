---
name: which-model
description: Choose the best-value model lane for a task by comparing capability, cost, context window, modality, latency, tool fit, and data policy. Use when the user invokes `/which-model`, asks which model to use, asks for value-for-token model suggestions, or wants session-level model-selection guidelines. `/which-model` with no arguments prints the guideline; `/which-model task prose or capability` returns 1-3 model suggestions.
---

# which-model

Choose by capability and cost for the job, not provider reputation. Treat OpenAI, Anthropic, Chinese models, and local/open-weight routes as first-class candidates.

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
1. qwen/qwen3-coder — best value for routine coding in this harness at $0.80/$3.20 per Mtok with 262k context
   Use for: targeted patches, refactors, and test writes under ~100k tokens of repo context
   Avoid if: task needs vision input or >200k output
   Availability: selectable here (openrouter)
2. anthropic/claude-sonnet-4 — fallback when the task needs strong tool-use or long-horizon agentic coding
   Use for: multi-file refactors, ambiguous specs requiring judgment
   Avoid if: cost-sensitive bulk subagent work
   Availability: selectable here
```

If filtering by hard requirements (data policy, modality, context, tools) leaves zero candidates, say so explicitly and recommend the closest relaxable constraint rather than inventing a match.

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
