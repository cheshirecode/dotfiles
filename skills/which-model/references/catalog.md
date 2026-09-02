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

Run `bin/model-catalog` from the skill root (the directory holding `SKILL.md`)
before recommending exact models:

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
- Age is measured from `data_as_of` (the date of the underlying data), not from when
  the cache file was written. Rebuilding a static snapshot or seed profile does not
  make it fresh, so `stale`/`very_stale` stay true until the source data itself moves.
- Always refresh for current/latest/live availability or pricing.

## Record and source requirements

Catalog records should include model id, provider, current-harness availability, known input/output price per million tokens, context window, max output, capabilities, caveats, confidence, and normalized `task_fit` tags.

Prefer official or harness-native, key-free sources:

- OpenCode configured models and Models.dev for OpenCode.
- Codex/OpenAI: **no live source is wired up.** `--env codex` (and `--provider codex`)
  always falls through to the hand-written `ENV_SEEDS["codex"]` records, which are
  marked `requires_harness_check` and carry an unverified-provenance caveat. Treat
  their IDs, prices, and context windows as a starting shortlist to confirm in the
  harness and against OpenAI's pricing page — never as a quotable source.
- Cursor local `state.vscdb` reactive storage (`availableDefaultModels2`) for Cursor.
- Public OpenRouter models API (`https://openrouter.ai/api/v1/models`) for OpenRouter.
- For Claude, the helper's dated Anthropic docs snapshot enriched with pricing/limits. When live availability matters, let the running session inject model JSON through `WHICH_MODEL_CATALOG_SOURCE`; the skill must never hold an Anthropic API key.

Label prices or availability as unverified when the source cannot prove them. State whether each recommended route is selectable here, requires a wrapper, or is unavailable in the harness.
