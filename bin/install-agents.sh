#!/usr/bin/env bash
# Link portable agent definitions and global instructions into user config directories:
#   - OpenCode agents: ~/.config/opencode/agents/*.md
#   - Claude Code agents: ~/.claude/agents/*.md
#   - Global Claude instructions: ~/.claude/CLAUDE.md
#
# Idempotent. Re-running safely updates or skips unchanged links.

set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help)
    cat <<'EOF'
usage: bin/install-agents.sh [--dry-run]
  --dry-run  print intended actions without changing files
EOF
    exit 0
    ;;
  *) echo "install-agents: unknown flag $1" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCODE_SOURCE_DIR="$REPO_ROOT/.config/opencode/agents"
OPENCODE_TARGET_DIR="${OPENCODE_AGENT_TARGET_DIR:-$HOME/.config/opencode/agents}"

CLAUDE_AGENT_SOURCE_DIR="$REPO_ROOT/.claude/agents"
CLAUDE_AGENT_TARGET_DIR="${CLAUDE_AGENT_TARGET_DIR:-$HOME/.claude/agents}"

CLAUDE_INSTRUCTION_SOURCE="$REPO_ROOT/.claude/CLAUDE.md"
CLAUDE_INSTRUCTION_TARGET="${CLAUDE_INSTRUCTION_TARGET:-$HOME/.claude/CLAUDE.md}"

link_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  # If source and destination resolve to the same canonical path, nothing to do
  if [[ -e "$src" && -e "$dst" ]] && [[ "$(realpath "$src")" == "$(realpath "$dst")" ]]; then
    return 0
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    local backup="$dst.pre-dotfiles"
    if [[ -e "$backup" || -L "$backup" ]]; then
      echo "install-agents: refusing to overwrite existing backup: $backup" >&2
      exit 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] move $dst to $backup"
    else
      mv "$dst" "$backup"
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] link $src to $dst"
  else
    ln -s "$src" "$dst"
    echo "  linked $label: $dst"
  fi
}

# 1. OpenCode agents
if [[ -d "$OPENCODE_SOURCE_DIR" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$OPENCODE_TARGET_DIR"
  fi
  for source_agent in "$OPENCODE_SOURCE_DIR"/*.md; do
    [[ -e "$source_agent" ]] || continue
    agent_name="$(basename "$source_agent")"
    link_file "$source_agent" "$OPENCODE_TARGET_DIR/$agent_name" "OpenCode agent"
  done
fi

# 2. Claude Code agents
if [[ -d "$CLAUDE_AGENT_SOURCE_DIR" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$CLAUDE_AGENT_TARGET_DIR"
  fi
  for source_agent in "$CLAUDE_AGENT_SOURCE_DIR"/*.md; do
    [[ -e "$source_agent" ]] || continue
    agent_name="$(basename "$source_agent")"
    link_file "$source_agent" "$CLAUDE_AGENT_TARGET_DIR/$agent_name" "Claude agent"
  done
fi

# 3. Global Claude instructions
if [[ -f "$CLAUDE_INSTRUCTION_SOURCE" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$(dirname "$CLAUDE_INSTRUCTION_TARGET")"
  fi
  link_file "$CLAUDE_INSTRUCTION_SOURCE" "$CLAUDE_INSTRUCTION_TARGET" "global instructions"
fi
