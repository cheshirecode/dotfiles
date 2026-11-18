#!/usr/bin/env bash
# Link portable agents and global instructions into user config directories:
#   - OpenCode agents: ~/.config/opencode/agents/*.md
#   - OpenCode skills: ~/.config/opencode/skills/<name>/
#   - Claude Code agents: ~/.claude/agents/*.md
#   - Global Claude instructions: ~/.claude/CLAUDE.md

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
SKILL_SOURCE_DIR="$REPO_ROOT/.config/opencode/skills"
SKILL_TARGET_DIR="$HOME/.config/opencode/skills"

CLAUDE_AGENT_SOURCE_DIR="$REPO_ROOT/.claude/agents"
CLAUDE_AGENT_TARGET_DIR="${CLAUDE_AGENT_TARGET_DIR:-$HOME/.claude/agents}"

CLAUDE_INSTRUCTION_SOURCE="$REPO_ROOT/.claude/CLAUDE.md"
CLAUDE_INSTRUCTION_TARGET="${CLAUDE_INSTRUCTION_TARGET:-$HOME/.claude/CLAUDE.md}"

# One link discipline for both kinds: leave an already-correct link alone, move
# anything else aside once, then link. Agents are files and skills are
# directories; ln -s and the -e/-L tests treat them identically.
link_into() {
  local source="$1" target="$2" kind="$3" backup
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    return
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    backup="$target.pre-dotfiles"
    if [[ -e "$backup" || -L "$backup" ]]; then
      echo "install-opencode: refusing to overwrite existing backup: $backup" >&2
      exit 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] move $target to $backup"
    else
      mv "$target" "$backup"
    fi
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] link $source to $target"
  else
    ln -s "$source" "$target"
    echo "  linked $kind: $target"
  fi
}

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$AGENT_TARGET_DIR"
fi
for source_agent in "$AGENT_SOURCE_DIR"/*.md; do
  link_into "$source_agent" "$AGENT_TARGET_DIR/$(basename "$source_agent")" agent
done

# Skills were tracked here but linked by no installer, so the only copy on the
# machine was a hand-placed directory: a second source of truth that drifts
# from the repo with nothing able to see it. Every other skill root on this box
# is symlinks into the checkout; this makes OpenCode match.
if [[ -d "$SKILL_SOURCE_DIR" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$SKILL_TARGET_DIR"
  fi
  for source_skill in "$SKILL_SOURCE_DIR"/*/; do
    source_skill="${source_skill%/}"
    [[ -d "$source_skill" ]] || continue
    link_into "$source_skill" "$SKILL_TARGET_DIR/$(basename "$source_skill")" skill
  done
fi

# Claude agents and global instructions: same link discipline. The target
# vars are overridable so test sandboxes can redirect them.
if [[ -d "$CLAUDE_AGENT_SOURCE_DIR" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$CLAUDE_AGENT_TARGET_DIR"
  fi
  for source_agent in "$CLAUDE_AGENT_SOURCE_DIR"/*.md; do
    [[ -e "$source_agent" ]] || continue
    link_into "$source_agent" "$CLAUDE_AGENT_TARGET_DIR/$(basename "$source_agent")" "Claude agent"
  done
fi

if [[ -f "$CLAUDE_INSTRUCTION_SOURCE" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$(dirname "$CLAUDE_INSTRUCTION_TARGET")"
  fi
  link_into "$CLAUDE_INSTRUCTION_SOURCE" "$CLAUDE_INSTRUCTION_TARGET" "global instructions"
fi
