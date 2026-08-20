---
name: pr-cost
description: Collect a typed AI cost payload for a newly created GitHub PR, persist it to a local ledger, and optionally post an idempotent PR comment when live writes are explicitly enabled.
---

# pr-cost

Use this skill from harness-specific hook adapters after a successful `gh pr create`.
It is dry by default: it always prefers the local ledger, and it only writes a
GitHub PR comment when `PR_COST_HOOK_LIVE=1`.

## Files

- Collector: `scripts/pr_cost_collect.py`
- Tests: `tests/test_pr_cost_collect.py`
- Fixtures: `tests/fixtures/`

## Contract

The collector emits one JSON object with this required shape:

```json
{
  "schema_version": "pr-cost/v1",
  "harness": "claude | cursor | codex",
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

## Privacy rules

- Never copy prompts, responses, file contents, or shell output beyond the PR URL.
- Never store API keys, tokens, auth headers, or repo-local secrets.
- Prefer safe metadata only: harness, model, token counts, session identifier,
  bounded timestamps, PR URL, and a short note about confidence.
- Cursor and Codex adapters should treat unavailable data as `null`, not as a
  reason to scrape unrelated local state.

## Harness guidance

- `cursor`: hook payload can detect `gh pr create`, but it does not expose
  token or USD usage. Default confidence is `unavailable`.
- `claude`: `PostToolUse` can observe `gh pr create`. If an adapter already has
  token or pricing inputs, pass them as CLI flags so the collector can emit an
  `estimated` payload. Otherwise it will fall back to `unavailable`.
- `codex`: there is no native PR creation hook. Use a wrapper that feeds a
  matching hook JSON shape to `from-hook`, or call `emit` / `annotate`
  directly with explicit payload fields.

## Environment

- `PR_COST_LEDGER`: optional ledger override. Defaults to
  `~/.local/share/pr-cost/ledger.jsonl`.
- `PR_COST_HOOK_LIVE=1`: enables live `gh pr comment` writes. Unset keeps the
  collector dry and ledger-only.

## Commands

Validate and print a payload:

```bash
/opt/homebrew/bin/python3 scripts/pr_cost_collect.py emit \
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
/opt/homebrew/bin/python3 scripts/pr_cost_collect.py annotate \
  --fixture tests/fixtures/emit_valid.json
```

Run from a hook adapter by piping the native hook JSON to stdin:

```bash
printf '%s\n' '{"command":"gh pr create ...","exit_code":0,"stdout":"https://github.com/owner/repo/pull/123"}' \
  | /opt/homebrew/bin/python3 scripts/pr_cost_collect.py from-hook \
      --harness cursor
```

`from-hook` is fail-open by design:

- It ignores `gh pr view`, `gh pr comment`, and unrelated commands.
- It exits `0` on parse failures so the harness never blocks PR creation.
- It skips duplicate annotations when the ledger already contains the same
  `pr_url` and `session_id`.
