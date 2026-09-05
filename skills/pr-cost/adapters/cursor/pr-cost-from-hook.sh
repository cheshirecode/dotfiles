#!/bin/sh

stdin_json=$(cat)

printf '%s' "$stdin_json" | /opt/homebrew/bin/python3 \
  /Users/fredtran/Documents/oss/dotfiles/skills/pr-cost/scripts/pr_cost_collect.py \
  from-hook \
  --harness cursor >/dev/null 2>&1 || true

printf '{}\n'
