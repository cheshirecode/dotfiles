# Model catalog reference

Read this file when a request needs an exact model, current availability or pricing, billing impact, or environment/provider-specific routing.

## Environment and source

Cache an environment-specific model catalog because Codex, Claude, Cursor, OpenCode, and unknown harnesses expose different models, tools, policies, and billing. `--env` selects the harness/session; `--provider` independently selects the catalog source and defaults to the resolved environment.

Without `--env`, `WHICH_MODEL_ENV` wins. Active session markers and bounded process ancestry outrank passive home/config/credential evidence such as `CODEX_HOME`, cwd config directories, or provider API keys.

Catalog paths:

- Omitted provider: `$XDG_CACHE_HOME/which-model/catalog.<env>.json`
- Explicit provider: `$XDG_CACHE_HOME/which-model/catalog.<env>.<provider>.json`
- Fallback root: `~/.cache/which-model/`
- Temporary/test root: `$WHICH_MODEL_CACHE_HOME/`

## Helper

Run `bin/model-catalog` from the skill root before recommending exact models:

```bash
bin/model-catalog --env auto --refresh-if-stale
bin/model-catalog --env opencode --refresh-if-stale --task routine_coding --top 3
bin/model-catalog --env opencode --provider openrouter --refresh-if-stale
```

Refresh rules:

- Missing cache: build before answering.
- Less than three days old: use silently for routine routing.
- Three to five days old: use for rough routing; refresh before exact prices or material billing decisions.
- More than five days old: refresh first; if refresh fails, use it only with a stale warning.
- Always refresh for current/latest/live availability or pricing.

## Record and source requirements

Catalog records should include model id, provider, current-harness availability, known input/output price per million tokens, context window, max output, capabilities, caveats, confidence, and normalized `task_fit` tags.

Prefer official or harness-native, key-free sources:

- OpenCode configured models and Models.dev for OpenCode.
- OpenAI model docs/API surfaces for Codex/OpenAI.
- Cursor local `state.vscdb` reactive storage (`availableDefaultModels2`) for Cursor.
- Public OpenRouter models API (`https://openrouter.ai/api/v1/models`) for OpenRouter.
- For Claude, the helper's dated Anthropic docs snapshot enriched with pricing/limits. When live availability matters, let the running session inject model JSON through `WHICH_MODEL_CATALOG_SOURCE`; the skill must never hold an Anthropic API key.

Label prices or availability as unverified when the source cannot prove them. State whether each recommended route is selectable here, requires a wrapper, or is unavailable in the harness.
