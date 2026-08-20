# Install PR cost hooks

Annotates a newly created GitHub PR with estimated AI session cost. Default is
**ledger only** (`~/.local/share/pr-cost/ledger.jsonl`). GitHub comments stay
off unless `PR_COST_HOOK_LIVE=1`.

Collector:

```bash
/opt/homebrew/bin/python3 skills/pr-cost/scripts/pr_cost_collect.py from-hook --harness <cursor|claude|codex>
```

## Cursor (installed on this machine)

User-global:

- `~/.cursor/hooks.json` — `afterShellExecution` matcher `\bgh\s+pr\s+create\b`
- `~/.cursor/hooks/pr-cost-from-hook.sh` — fail-open wrapper → collector `--harness cursor`

Reload: Cursor watches `hooks.json`. If it does not fire, restart Cursor and
check the Hooks output channel.

Versioned copy: `adapters/cursor/`.

## Claude Code (installed on this machine)

- `~/.claude/settings.json` `hooks.PostToolUse` matcher `Bash(gh pr create:*)`
- `~/.claude/hooks/pr-cost-from-hook.sh` → `adapters/claude/v1/pr_cost_from_hook.py`

Existing worklog `PreCompact` / `SessionEnd` hooks must stay. Do not set
`attribution.pr`.

## Codex (opt-in, not on PATH)

Codex has no native PR-create hook. Prepend only in shells where Codex runs `gh`:

```bash
export PATH="$HOME/Documents/oss/dotfiles/skills/pr-cost/adapters/codex/bin:$PATH"
```

See `adapters/codex/README.md`. Do not shadow `/opt/homebrew/bin/gh` globally.

## Enable live PR comments (off by default)

```bash
export PR_COST_HOOK_LIVE=1
```

The collector posts an idempotent `gh pr comment`. Duplicate `pr_url` +
`session_id` rows are skipped.

## Verify without a live PR

```bash
/opt/homebrew/bin/python3 -m unittest discover -s skills/pr-cost/tests -q
```

That suite includes a `from-hook` fixture that writes a temp ledger and fails
if `gh` is invoked while `PR_COST_HOOK_LIVE` is unset.
