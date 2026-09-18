#!/usr/bin/env bash
# Register vendor skills without duplicating Codex's shared discovery root.
set -euo pipefail

bu_bin="${1:-browser-use}"
shared="$HOME/.agents/skills/browser-use/SKILL.md"
legacy="$HOME/.codex/skills/browser-use"

# Migrate only an ordinary, identical, single-file legacy directory. Preserve
# local edits, symlinks and supporting files. Back up outside discovery roots.
if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
  shopt -s nullglob dotglob
  entries=("$legacy"/*)
  if [ "${#entries[@]}" -eq 1 ] && [ -f "$legacy/SKILL.md" ] &&
     [ ! -L "$legacy/SKILL.md" ] && [ -f "$shared" ] &&
     cmp -s "$shared" "$legacy/SKILL.md"; then
    backup_root="$HOME/.local/state/browser-use-setup"
    mkdir -p "$backup_root"
    backup="$(mktemp -d "$backup_root/duplicate.XXXXXX")"
    mv "$legacy" "$backup/browser-use"
    printf 'Archived duplicate Codex skill: %s\n' "$backup/browser-use"
  else
    printf 'Preserved customized Codex skill: %s\n' "$legacy" >&2
  fi
fi

# Codex discovers .agents/skills. Keep the other vendor destinations supported;
# never call the vendor's default "all", which recreates .codex/skills too.
# The parent installer already installed the package, so do not upgrade again.
for target in agents claude copilot cursor gemini openclaw opencode; do
  "$bu_bin" skill install --target "$target" --no-install
done
