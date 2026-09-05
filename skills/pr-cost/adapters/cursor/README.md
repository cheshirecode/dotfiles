# Cursor PR cost hook adapter

This adapter installs a user-global Cursor hook that watches successful
`gh pr create` shell commands and forwards the hook JSON to the shared
`pr_cost_collect.py` collector.

## Files

- `hooks.json`: sample user-level Cursor hook config
- `pr-cost-from-hook.sh`: thin wrapper that reads hook stdin JSON and pipes it
  to the shared collector with `--harness cursor`

## Install

Cursor user hooks run from `~/.cursor/`, so the live config should be:

- `~/.cursor/hooks.json`
- `~/.cursor/hooks/pr-cost-from-hook.sh`

Install by copying these files into `~/.cursor/`, or point your existing
`~/.cursor/hooks.json` entry at the shared wrapper path if you prefer to keep
the dotfiles copy as the source of truth.

The recommended `afterShellExecution` hook entry is:

```json
{
  "version": 1,
  "hooks": {
    "afterShellExecution": [
      {
        "command": "./hooks/pr-cost-from-hook.sh",
        "matcher": "\\bgh\\s+pr\\s+create\\b",
        "failClosed": false
      }
    ]
  }
}
```

The wrapper intentionally fails open, emits only `{}` for Cursor's hook
response, and does not set `PR_COST_HOOK_LIVE`.
