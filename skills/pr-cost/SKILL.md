---
name: pr-cost
description: Record a typed AI cost payload for a newly created GitHub PR in a local ledger, and post an idempotent PR comment when live writes are explicitly enabled. Claude Code only; manual session-usage flow carries the real numbers.
---

# pr-cost

Attach "what did this PR cost in AI usage" to the PR itself: a typed JSON
payload in a local ledger (`~/.local/share/pr-cost/ledger.jsonl`), and — only
with `PR_COST_HOOK_LIVE=1` — an idempotent `gh pr comment`.

## What is real and what is not

Two paths exist, and they are honest about different things (this section
exists because the 2026-09-05 review council proved the earlier framing
wrong — items 10 and 13):

1. **Automatic (hook)**: a Claude Code `PostToolUse` hook pipes the payload
   of a successful `gh pr create` through the adapter. Hook payloads carry
   **no usage fields** — no config changes that — so the automatic entry
   records the PR/session pairing with `confidence: unavailable`, never
   invented numbers. It is a placeholder that something happened, keyed for
   dedup by `(pr_url, session_id)`.
2. **Manual (real numbers)**: `scripts/claude_session_usage.py --jsonl
   <session file>` sums the session's unique assistant-message usage; feed
   its output to `annotate`. **Caveat**: this sums the whole session — a
   session that opened two PRs or did unrelated work will over-attribute.
   Bound the window yourself (`--window-start/--window-end`) when it matters.

## Layout

- `scripts/pr_cost_collect.py` — schema validation (`pr-cost/v1`), ledger
  append with dedup, `emit` / `annotate` / `from-hook` subcommands.
- `scripts/claude_session_usage.py` — the manual flow's engine.
- `adapters/claude/v1/pr_cost_from_hook.py` — PostToolUse normalizer; resolves
  the collector relative to itself and runs under `sys.executable` (no
  machine-specific paths).
- `tests/` — every negative case proven red by mutation; `from-hook` is
  exercised with the raw fixture and no `--harness` flag; live mode is proven
  end-to-end against a PATH-stubbed `gh`.

Cursor and Codex adapters were removed by the same council: Cursor exposes no
usage data at all, and the Codex path required an uninstalled `gh`-shadowing
wrapper — speculative scaffolding for data that cannot exist. Re-add an
adapter only with a demonstrated data source.

## Install (Claude Code)

The skill installs like every other one here (`manifest/skills.yaml` →
`bin/install-skills.sh`). Wire the hook in `~/.claude/settings.json`:

```json
{ "hooks": { "PostToolUse": [{ "matcher": "Bash(gh pr create:*)",
  "hooks": [{ "type": "command",
    "command": "python3 ~/.claude/skills/pr-cost/adapters/claude/v1/pr_cost_from_hook.py" }] }] } }
```

Dry by default. `PR_COST_HOOK_LIVE=1` enables the PR comment;
`PR_COST_LEDGER` overrides the ledger path. Those two env vars are defined
here and only here.

## Manual flow

```bash
python3 scripts/claude_session_usage.py --jsonl ~/.claude/projects/<proj>/<session>.jsonl \
  | python3 scripts/pr_cost_collect.py annotate --fixture /dev/stdin --harness claude \
      --pr-url https://github.com/<owner>/<repo>/pull/<n>
PR_COST_HOOK_LIVE=1  # add to actually post the comment
```

Exit codes: `0` ok (including fail-open `{"status": "ignored"}` from
`from-hook`), `2` invalid payload.
