# Checking the rate model against billed cost

Every other lane in this skill reports an estimate. The opencode lane records
what the provider actually billed, next to the token split that produced it.
That makes it the one place where a cache-pricing claim can be checked against
money instead of asserted from a list price.

Use this before changing a rate table, adding a rate flag, or accepting a
claim that cache reads or writes cost some multiple of input.

## The data

`~/.local/share/opencode/opencode.db`, SQLite, several GB. Open it read-only
so a live opencode process keeps its write lock:

```bash
sqlite3 "file:$HOME/.local/share/opencode/opencode.db?mode=ro" '.tables'
```

Two places carry cost beside the split:

- table `session` — `cost`, `tokens_input`, `tokens_output`,
  `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`, `model`
- table `message`, inside the `data` JSON — `$.cost`, `$.tokens.input`,
  `$.tokens.output`, `$.tokens.reasoning`, `$.tokens.cache.read`,
  `$.tokens.cache.write`, `$.time.created`, `$.time.completed`, `$.modelID`,
  `$.finish`

`model` is a JSON blob, not a name: extract `$.id` before grouping.

## Why a fit works

`tokens_input` here **excludes** cache reads and writes — the three classes are
disjoint. Verified 2026-09-15: one `anthropic/claude-opus-4.7` group held
`tokens_input=427` against `tokens_cache_read=51,390,348`. A reader who
assumed inclusion would have subtracted 51M tokens from 427.

Because they are disjoint, a least-squares fit of `cost` on the token columns
recovers the per-token rates the provider charged.

## What it showed

Over 45,351 assistant messages and 1,233 billed sessions:

| model | n | R² | cache read | cache write |
|---|---|---|---|---|
| `openai/gpt-5.6-sol` | 816 | 0.9993 | 10.2% of input | 1.25x input |
| `openai/gpt-5.6-luna-pro` | 1006 | 0.9968 | 10.4% of input | 1.27x input |

Those multipliers match what `claude_session_usage.py` already encodes
(`cache_read=0.1x`, `cache_write_5m=1.25x`), so the rate *structure* is
confirmed against real money.

Competing readings lose badly. Same sessions, `gpt-5.6-sol`:

| pricing model | R² | mean error |
|---|---|---|
| four disjoint classes | 0.999996 | $0.011 |
| input includes cache tokens | 0.999677 | $0.171 |
| cache reads free | 0.999394 | $0.245 |

Note how little R² separates them while mean error moves 16x. **Report mean
and max residual, not R² alone** — on a spread of session sizes R² stays near
1 for any roughly-proportional model, so it cannot tell a right split from a
wrong one.

## What it cannot show

- **Latency.** Regressing request latency on the same columns gives R²
  0.04-0.67 and negative cache coefficients on two models. Generation time
  (~18-22 ms per 1k output tokens) and 2.4-16.6 s of fixed overhead swamp
  prefill. Do not claim a cache latency win from this database.
- **Cross-host cache sharing.** No table carries a host, machine or device
  column. Single-machine data cannot show a shared cache.
- **Your account's rates.** These are openrouter prices including its margin.
  Treat a recovered rate as evidence about structure — which classes cost what
  multiple of input — never as a number to paste into a provider rate table.
  Pasting one in is the invented-rate defect the readers exist to avoid.
