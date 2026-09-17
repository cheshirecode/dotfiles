#!/usr/bin/env bash
# Wire bin/git-hooks/ into this clone.
#
#   install-hooks.sh          dry run
#   install-hooks.sh --write  apply
#
# Sets core.hooksPath, or symlinks into .git/hooks/ when an outer
# (system/global) core.hooksPath is already set, so an existing scanner there
# keeps running.

set -uo pipefail

WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1
ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd "$ROOT" || exit 1

outer="$(git config --system --get core.hooksPath 2>/dev/null || true)"
[ -n "$outer" ] || outer="$(git config --global --get core.hooksPath 2>/dev/null || true)"

if [ -n "$outer" ]; then
  mode="chain into .git/hooks/ (outer core.hooksPath present: $outer)"
else
  mode="set core.hooksPath=bin/git-hooks"
fi
echo "install-hooks: $mode"

if [ "$WRITE" != "1" ]; then
  echo "  (dry run; pass --write to apply)"
  exit 0
fi

if [ -n "$outer" ]; then
  mkdir -p .git/hooks
  for h in bin/git-hooks/*; do
    n="$(basename "$h")"
    ln -sfn "../../$h" ".git/hooks/$n" && echo "  linked .git/hooks/$n"
  done
else
  git config core.hooksPath bin/git-hooks && echo "  core.hooksPath=bin/git-hooks"
fi
echo "install-hooks: done. Bypass a single commit with DOTFILES_NO_HOOK=1."
