# Cost payload and harness contract

Run commands from the skill directory.

## Contract

The collector emits one JSON object with this required shape:

```json
{
  "schema_version": "pr-cost/v1",
  "harness": "claude | cursor | codex | opencode",
  "confidence": "metered | estimated | unavailable",
  "usd": 1.23,
  "tokens_in": 1200,
  "tokens_out": 3400,
  "model": "claude-sonnet-4-20250514",
  "session_id": "session-123",
  "window_start": "2026-08-20T19:00:00+00:00",
  "window_end": "2026-08-20T19:05:00+00:00",
  "pr_url": "https://github.com/owner/repo/pull/123",
  "generated_at": "2026-08-20T19:05:01+00:00",
  "notes": "optional"
}
```

`usd`, `tokens_in`, `tokens_out`, `model`, `session_id`, `pr_url`, and `notes`
may be `null` when the harness cannot supply them. The keys still remain
present so downstream adapters receive a stable typed contract.

### Reading `tokens_in`

`tokens_in` is the sum of three token classes that cost three different
amounts, so the total on its own cannot be multiplied by the input rate.
These five keys are additive and nullable — a payload written before they
existed still validates, and `schema_version` stays `pr-cost/v1`:

```json
{
  "tokens_in_uncached": 2956,
  "tokens_in_cache_read": 697885763,
  "tokens_in_cache_write": 22807403,
  "usd_basis": "model-rates | default-rates | provider-reported",
  "scope": "session-total | this-pr"
}
```

Why it matters: a posted comment once read `tokens_in 721,979,117` beside
`usd ~510`, and its reader took that as 722M tokens bought at input rates.
96.8% of it was cache reads, billed at a tenth of the input rate. The payload
held no field for the split, so the comment printed the merged number alone.

Two rules the collector enforces:

- When all three parts are present they must sum to `tokens_in`. A split that
  does not add up is worse than no split — both numbers reach the comment and
  a reader cannot tell which to believe.
- `scope` defaults to `session-total` whenever `tokens_in` is present. A
  session reader sums the whole session, which may cover other PRs and
  unrelated work; unlabelled, those numbers read as this PR's cost. Pass
  `--scope this-pr` only when the figures really were scoped to one PR.

`usd_basis` says how the dollar figure was reached. `default-rates` means flat
lane rates were used, *not* the rates of the model named in the payload — so
the number can look right while being priced from the wrong table.

## Harness guidance

- `cursor`: hook payload can detect `gh pr create`, but it does not expose
  token or USD usage. Default confidence is `unavailable`.
- `claude`: `PostToolUse` can observe `gh pr create`. If an adapter already has
  token or pricing inputs, pass them as CLI flags so the collector can emit an
  `estimated` payload. Otherwise it will fall back to `unavailable`.
- `codex`: there is no native PR creation hook. Use a wrapper that feeds a
  matching hook JSON shape to `from-hook`, or call `emit` / `annotate`
  directly with explicit payload fields.
- `opencode`: sessions live in SQLite at
  `~/.local/share/opencode/opencode.db`, not in a JSONL transcript, so its
  reader takes `--db` / `--session-id` / `--cwd` rather than a file path.
  Each assistant message carries the provider's own `cost`, so this lane
  reports what the provider billed instead of inferring a price, and its
  payload says `usd_basis: provider-reported`.

## Commands

Validate and print a payload:

```bash
python3 scripts/pr_cost_collect.py emit \
  --harness claude \
  --confidence estimated \
  --usd 1.23 \
  --tokens-in 1200 \
  --tokens-out 3400 \
  --model claude-sonnet-4-20250514 \
  --session-id session-123 \
  --window-start 2026-08-20T19:00:00+00:00 \
  --window-end 2026-08-20T19:05:00+00:00 \
  --pr-url https://github.com/owner/repo/pull/123
```

Append to the ledger and optionally comment on the PR:

```bash
python3 scripts/pr_cost_collect.py annotate \
  --fixture tests/fixtures/emit_valid.json
```

Run from a hook adapter by piping the native hook JSON to stdin:

```bash
printf '%s\n' '{"command":"gh pr create ...","exit_code":0,"stdout":"https://github.com/owner/repo/pull/123"}' \
  | python3 scripts/pr_cost_collect.py from-hook \
      --harness cursor
```

`from-hook` is fail-open by design:

- It ignores `gh pr view`, `gh pr comment`, and unrelated commands.
- It exits `0` on parse failures so the harness never blocks PR creation.
- It skips duplicate annotations when the ledger already contains the same
  `pr_url` and `session_id`.
