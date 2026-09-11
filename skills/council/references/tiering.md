# Council: model tiering per stage

Read this before choosing models for a council stage.

Use `$which-model` for provider/model selection. Council owns the stage requirements; `which-model`
owns model comparison, pricing freshness, first-class Chinese-model treatment, harness availability,
and sequential-thinking decomposition. If `which-model` is unavailable, use the same principle:
pick the cheapest model lane that clears the stage's capability bar and is selectable here.

The council-specific mapping is (budget-aware, ~$50/2-3mo total):

- **Stage 1 research** — cheap tier for mechanical inventory/grep angles (`gemini-flash-latest`, `qwen/qwen3.5-flash`). Mid tier for judgment-bearing angles where trade-off analysis matters (`~anthropic/claude-sonnet-latest`, `google/gemini-2.5-pro`). Reserve frontier (`kimi-k3`, `claude-opus-latest`) only when the research angle is the single most consequential part of the council.
- **Stage 3 discussion** / **Stage 5 voting** — cheap-to-mid tier: adversarial application of criteria is structured work, not open-ended reasoning. `claude-haiku-latest`, `gemini-flash-latest`, or `deepseek-v4-flash` handle criterion checks cleanly. Escalate one voter to mid-tier only for high-stakes councils where a wrong vote materially costs real money/time.
- **Stage 4 collation** — cheap tier: dedupe + tag only, no invention authority (Iron Law), so it needs no reasoning headroom. Any cheap flash model suffices.
- **Stage 6 tally + conclusion** — the orchestrator itself (whatever your default model is). It already holds the full context; don't delegate this stage to another model unless your default can't handle the token count.

Cheap-token expansion rule:

- If Stage 1 inventory/search uses a cheap tier, prefer 4-5 narrow angles over 3 broad ones when the extra angle can test a real blind spot.
- If Stage 5 voting uses a cheap-enough mid tier, prefer 5 voters over 3 for high-impact or close-call decisions.
- Keep cheap expansion evidence-shaped: file/line refs, commands, source citations, explicit no-finding results. More cheap tokens are for coverage, not longer prose.

Budget gate: if a council would spawn >8 sub-agents across all stages at cheap-tier prices, or >3 at mid-tier, flag the estimate before proceeding. A $50 budget means each council should cost <$5 total. If your default model is flash-tier ($0.10/M tok input) and the council generates >50k tokens across all sub-agent outputs, you're already at $5 for one council.
