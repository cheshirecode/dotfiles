#!/usr/bin/env bash
# Link the portable OpenCode configuration into its global config location.

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
SOURCE="$REPO_ROOT/.config/opencode/opencode.jsonc"
TARGET="$HOME/.config/opencode/opencode.jsonc"
AGENT_SOURCE_DIR="$REPO_ROOT/.config/opencode/agents"
AGENT_TARGET_DIR="$HOME/.config/opencode/agents"

[[ -f "$SOURCE" ]] || { echo "install-opencode: source missing: $SOURCE" >&2; exit 1; }

if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  echo "  OpenCode config already linked: $TARGET"
  exit 0
fi

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  backup="$TARGET.pre-dotfiles"
  if [[ -e "$backup" || -L "$backup" ]]; then
    echo "install-opencode: refusing to overwrite existing backup: $backup" >&2
    exit 1
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] move $TARGET to $backup"
  else
    mv "$TARGET" "$backup"
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] link $SOURCE to $TARGET"
else
  mkdir -p "$(dirname "$TARGET")"
  ln -s "$SOURCE" "$TARGET"
  echo "  linked OpenCode config: $TARGET"
fi

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
