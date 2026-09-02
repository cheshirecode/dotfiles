# Task routing reference

Read this file for `/which-model <task prose or capability>`. Apply the root data-policy gate first. Read `catalog.md` as well only when the request needs exact/current model or harness information.

## Routing heuristics

- **Mechanical search, inventory, or status:** choose the cheapest reliable model with enough context and tool access. DeepSeek/Qwen/MiniMax/MiMo-class lanes are first-class candidates.
- **Routine coding or targeted patching:** choose the cheapest model that reliably follows repo patterns and tests. Within Kimi/Moonshot recommendations, use `kimi-k3` as the current coding candidate when selectable, especially for long-horizon work or large codebases; use `kimi-k2.7-code-highspeed` only when faster output matters more. Do not infer cross-provider superiority from model-name task tags. Qwen coder, GLM/Z.ai, OpenAI mid, Anthropic Sonnet-class, or local code models can still win depending on harness and repo fit.
- **Long-context review:** prefer large context and low input cost, then require evidence-shaped output: file references, commands, pass/fail status, and uncertainty.
- **Voting or adversarial review:** use mid-tier judgment models. Use three voters by default; use five only when the decision is high-impact, close, and cheap enough.
- **Visual or design judgment:** require multimodal capability. Text-only cheap models can support surrounding search but cannot own the visual decision.
- **Accessibility review:** separate screenshot judgment from semantic checks. Visual models can inspect rendered state; keyboard flow, focus order, ARIA, contrast math, and screen-reader semantics require code inspection and/or deterministic accessibility tooling.
- **Final synthesis or conflict resolution:** use the strongest available model holding the whole thread when cost is justified.

## Selection discipline

- Filter first by policy, modality, context, tools, and selectability; compare price only among viable routes.
- State whether routing is enforceable in the current harness or merely advisory.
- Use cheap lanes for bounded mechanical work and mid-tier lanes for judgment. Escalate only the unresolved synthesis or high-risk decision.
- Prefer a lane over an exact model when availability has not been verified through `catalog.md`.

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

Concrete example (shape only — the model names and lane labels are illustrative,
and the numbers are deliberately absent because none were verified through
`catalog.md`):

```markdown
1. cheap long-context code lane — best value for routine coding in this harness: low input cost, context comfortably above the repo slice
   Use for: targeted patches, refactors, and test writes under ~100k tokens of repo context
   Avoid if: task needs vision input or very long output
   Availability: selectable here (openrouter)
2. claude-sonnet-5 — fallback when the task needs strong tool-use or long-horizon agentic coding
   Use for: multi-file refactors, ambiguous specs requiring judgment
   Avoid if: cost-sensitive bulk subagent work
   Availability: selectable here
```

If filtering by hard requirements (data policy, modality, context, tools) leaves zero candidates, say so explicitly and recommend the closest relaxable constraint rather than inventing a match.

Include exact prices only after reading `references/catalog.md` and obtaining a fresh enough snapshot. Otherwise compare qualitatively and label dated calibration as approximate.
