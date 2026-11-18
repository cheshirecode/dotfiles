---
name: pr-cost
description: Collect AI cost data for a PR into a local ledger when cost tracking is requested or a configured adapter invokes it. Posting requires live-write authorization.
---

# pr-cost

Collect session usage after successful PR creation. Prefer the local ledger;
GitHub comments require explicit authorization and `PR_COST_HOOK_LIVE=1`.
Resolve the skill directory from this file's load path and run commands there.

## Route first

- Hook setup or adapter installation: read [INSTALL.md](INSTALL.md).
- Construct or validate a payload, invoke a collector, or select a usage reader:
  read [references/payload.md](references/payload.md).
- Diagnose a harness lane: read [references/diagnosis.md](references/diagnosis.md).
- Add cost to an existing PR: read [references/annotate.md](references/annotate.md).
- Check a rate or cache-pricing claim against billed cost: read
  [references/billed-validation.md](references/billed-validation.md).

Load only the reference needed by the request. Adapters live in
`adapters/{cursor,claude,codex}/`; the collector is `scripts/pr_cost_collect.py`.

## Privacy rules

- Never copy prompts, responses, file contents, or shell output beyond the PR URL.
- Never store API keys, tokens, auth headers, or repo-local secrets.
- Prefer safe metadata only: harness, model, token counts, session identifier,
  bounded timestamps, PR URL, and a short note about confidence.
- Cursor and Codex adapters should treat unavailable data as `null`, not as a
  reason to scrape unrelated local state.

## Environment

- `PR_COST_LEDGER`: optional ledger override. Defaults to
  `~/.local/share/pr-cost/ledger.jsonl`.
- `PR_COST_HOOK_LIVE=1`: enables live `gh pr comment` writes. Unset keeps the
  collector dry and ledger-only.
