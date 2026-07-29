#!/usr/bin/env bash
# Link portable OpenCode agents into the global agent directory.

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help)
    cat <<'EOF'
usage: bin/install-opencode.sh [--dry-run]
  --dry-run  print intended actions without changing files
EOF
    exit 0
    ;;
  *) echo "install-opencode: unknown flag $1" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_SOURCE_DIR="$REPO_ROOT/.config/opencode/agents"
AGENT_TARGET_DIR="$HOME/.config/opencode/agents"

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$AGENT_TARGET_DIR"
fi
for source_agent in "$AGENT_SOURCE_DIR"/*.md; do
  agent_name="$(basename "$source_agent")"
  target_agent="$AGENT_TARGET_DIR/$agent_name"
  if [[ -L "$target_agent" && "$(readlink "$target_agent")" == "$source_agent" ]]; then
    continue
  fi
  if [[ -e "$target_agent" || -L "$target_agent" ]]; then
    backup="$target_agent.pre-dotfiles"
    if [[ -e "$backup" || -L "$backup" ]]; then
      echo "install-opencode: refusing to overwrite existing backup: $backup" >&2
      exit 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] move $target_agent to $backup"
    else
      mv "$target_agent" "$backup"
    fi
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] link $source_agent to $target_agent"
  else
    ln -s "$source_agent" "$target_agent"
    echo "  linked OpenCode agent: $target_agent"
  fi
done
