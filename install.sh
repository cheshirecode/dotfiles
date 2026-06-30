#!/usr/bin/env bash
# Custom installer for `coder dotfiles`. Replicates the default symlink
# behavior for top-level dotfiles, but copies .cursor into the destination
# instead of symlinking because ~/.cursor is a persistent-disk mountpoint
# on this workspace template (symlink-over-mountpoint fails).
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${CODER_SYMLINK_DIR:-$HOME}"

backup() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv "$target" "$target.bak"
    echo "Moved $target to $target.bak..."
  fi
}

# Symlink top-level dotfiles (anything matching .* except VCS/meta dirs).
for src in "$REPO_DIR"/.*; do
  name="$(basename "$src")"
  case "$name" in
    .|..|.git|.github|.gitignore) continue ;;
    .cursor) continue ;; # handled below
    .gitconfig.cheshireCode) continue ;; # referenced by absolute path from .gitconfig
    .envrc.github) continue ;; # gitignored secret holder, sourced explicitly
  esac
  target="$DEST/$name"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    continue
  fi
  backup "$target"
  echo "Symlinking $src to $target..."
  ln -s "$src" "$target"
done

# .cursor: copy contents instead of symlinking. ~/.cursor is a mountpoint;
# replacing it with a symlink fails with "file exists".
if [ -d "$REPO_DIR/.cursor" ]; then
  mkdir -p "$DEST/.cursor"
  echo "Copying $REPO_DIR/.cursor/ into $DEST/.cursor/..."
  cp -R "$REPO_DIR/.cursor/." "$DEST/.cursor/"
fi

# Symlink Claude Code skills shipped in this repo into ~/.claude/skills/.
# Code (skill + bin) is version-controlled here; per-machine data/config
# (e.g. worklog's WORKLOG_REPO) lives outside the repo via ~/.shell_common.local.
if [ -d "$REPO_DIR/skills" ]; then
  mkdir -p "$DEST/.claude/skills"
  for skill in "$REPO_DIR"/skills/*/; do
    sname="$(basename "$skill")"
    starget="$DEST/.claude/skills/$sname"
    if [ -L "$starget" ] && [ "$(readlink "$starget")" = "${skill%/}" ]; then
      continue
    fi
    backup "$starget"
    echo "Symlinking skill $sname into $starget..."
    ln -s "${skill%/}" "$starget"
  done
fi

# Bootstrap ~/.gitconfig.local (machine-local identity, untracked). The
# committed .gitconfig pulls it in via [include]; without it, git complains
# about a missing include path on every invocation.
if [ ! -e "$DEST/.gitconfig.local" ]; then
  echo "Creating empty $DEST/.gitconfig.local — fill in [user] for this machine."
  cat > "$DEST/.gitconfig.local" <<'EOF'
# Per-machine git identity. Add a [user] block here; do not commit this file.
[user]
	# name = Your Name
	# email = you@example.com
EOF
fi

echo "Dotfiles installation complete."
