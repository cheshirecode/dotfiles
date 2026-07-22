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
