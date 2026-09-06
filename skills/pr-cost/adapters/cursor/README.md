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

Install by pointing your `~/.cursor/hooks.json` entry at the versioned
wrapper in this directory. That is the preferred shape: the wrapper finds the
collector from its own location, so it needs no configuration.

If you copy the files into `~/.cursor/` instead, the copy has no skill
directory above it and cannot find the collector on its own. Export the path
for that install:

```bash
export PR_COST_COLLECTOR="$(git rev-parse --show-toplevel)/skills/pr-cost/scripts/pr_cost_collect.py"
```

Without it the hook still replies `{}` and never blocks `gh pr create`; it
simply records nothing.

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
