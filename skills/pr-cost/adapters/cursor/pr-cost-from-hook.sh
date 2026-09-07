#!/bin/sh
# Resolve the collector from this script's own location, so the adapter works
# in any checkout rather than only the author's. adapters/cursor/ -> ../.. is
# the skill root.
#
# One install path defeats that: the README offers COPYING this file into
# ~/.cursor/hooks/, where no skill directory sits above it. Point the
# ~/.cursor/hooks.json entry at the versioned copy instead, or export
# PR_COST_COLLECTOR to the collector's absolute path for a copied install.
#
# The fail-open behavior below is deliberate and must stay: `|| true`, the
# discarded output, and the unconditional `{}` reply. A hook that breaks
# `gh pr create` is worse than a hook that silently records nothing.

stdin_json=$(cat)

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
collector="$script_dir/../../scripts/pr_cost_collect.py"
if [ ! -f "$collector" ]; then
  collector="${PR_COST_COLLECTOR:-}"
fi

if [ -n "$collector" ] && [ -f "$collector" ]; then
  printf '%s' "$stdin_json" | python3 "$collector" \
    from-hook \
    --harness cursor >/dev/null 2>&1 || true
fi

printf '{}\n'
