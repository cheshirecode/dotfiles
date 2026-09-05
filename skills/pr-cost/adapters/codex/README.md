# Codex PR-cost adapter

Codex does not expose a native PR-creation hook, so this adapter uses the
least-bad fallback from the survey: an opt-in `gh` wrapper that watches for
successful `gh pr create` commands and forwards a hook-shaped JSON payload to:

```bash
/opt/homebrew/bin/python3 /Users/fredtran/Documents/oss/dotfiles/skills/pr-cost/scripts/pr_cost_collect.py from-hook --harness codex
```

The wrapper is versioned under this skill instead of inventing new
`~/.codex/config.toml` keys or replacing Codex's existing `notify` behavior.

## Install

Prepend this adapter directory to `PATH` for the shell where Codex runs `gh`:

```bash
export PATH="/Users/fredtran/Documents/oss/dotfiles/skills/pr-cost/adapters/codex/bin:$PATH"
```

If the real GitHub CLI is not `/opt/homebrew/bin/gh`, point the wrapper at it
explicitly:

```bash
export PR_COST_REAL_GH="/absolute/path/to/gh"
```

This task does not install the wrapper globally, does not edit `~/.codex`, and
does not set `PR_COST_HOOK_LIVE`.

## Behavior

- Calls the real `gh` binary and preserves its exit code, stdout, and stderr.
- Only invokes the collector for `gh pr create`.
- Uses the collector's existing fail-open `from-hook` path, so annotation
  failures never block PR creation.
- Leaves PR comments disabled unless someone explicitly exports
  `PR_COST_HOOK_LIVE=1` outside this adapter.

## Uninstall

Remove the adapter directory from `PATH`, or unset the override if you set one:

```bash
unset PR_COST_REAL_GH
```
