# which-model Provider Catalog Handover

Use this prompt to hand a provider-specific catalog implementation to another session.

```text
You are working in /Users/fredtran/Documents/oss/dotfiles.

Goal: extend skills/which-model/bin/model-catalog for one provider or harness so /which-model
builds a real environment-specific catalog instead of relying on seeded fallback data.

Current contract:
- Canonical skill: skills/which-model/SKILL.md
- Helper: skills/which-model/bin/model-catalog
- Cache paths: omitted provider uses $XDG_CACHE_HOME/which-model/catalog.<env>.json; explicit provider uses $XDG_CACHE_HOME/which-model/catalog.<env>.<provider>.json; fallback root is ~/.cache/which-model/
- Test surface: tests/run.sh fixtures has "which-model catalog warms legacy env cache"
- Cache records must include:
  id, display_name, provider, availability, input_price_per_mtok, output_price_per_mtok,
  context_window, max_output, capabilities, task_fit, caveats, confidence.
- Writes must be atomic.
- Missing or stale cache should be refreshed before exact model recommendations.

Provider target: <codex|opencode|claude|cursor|openrouter|other>

Implementation rules:
1. Use the harness-native source first when it exists.
   - Codex/OpenAI: OpenAI model docs/API surfaces; the OpenAI list-models endpoint gives model IDs,
     but not complete pricing/capability metadata, so enrich from official model docs or a checked
     provider metadata source.
   - OpenCode: prefer `opencode models` for local availability and Models.dev for model metadata.
   - Claude: prefer Anthropic Models API for availability/capabilities/token limits and official
     Anthropic pricing docs for price fields.
   - Cursor: prefer local Cursor-discoverable model state if available; otherwise keep availability
     `unverified_in_harness` and document the source.
   - OpenRouter: use OpenRouter model API metadata for model IDs, context, architecture, pricing,
     supported parameters, and provider caveats.
2. Never silently quote exact pricing from old or inferred data. Use `confidence` and `caveats`.
3. Preserve seeded fallback behavior for offline operation.
4. Add deterministic tests with a local JSON fixture; do not make CI depend on live provider APIs.
5. Run:
   tests/run.sh fixtures
   tests/run.sh static
6. Dogfood the target:
   skills/which-model/bin/model-catalog --env <target> --refresh-if-stale --task routine_coding --top 3
   Confirm the reported cache path exists and the recommendations are target-specific.

Expected output:
- Code changes to skills/which-model/bin/model-catalog and tests/run.sh.
- Optional SKILL.md wording only if the contract changes.
- A short note identifying the live source used, fields populated, fallback behavior, and dogfood
  cache path.
```
