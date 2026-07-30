#!/usr/bin/env bash
# Custom installer for `coder dotfiles`. Replicates the default symlink
# behavior for top-level dotfiles, but copies .cursor into the destination
# instead of symlinking because ~/.cursor is a persistent-disk mountpoint
# on this workspace template (symlink-over-mountpoint fails).
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
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
    .config) continue ;; # handled below — repo lives under ~/.config, symlinking it wholesale creates a self-referential loop
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

# .config: link children individually. Coder clones this repo into
# ~/.config/coderv2/dotfiles, so symlinking ~/.config at the top level would
# point the directory into itself ("Too many levels of symbolic links").
if [ -d "$REPO_DIR/.config" ]; then
  mkdir -p "$DEST/.config"
  for entry in "$REPO_DIR"/.config/*; do
    [ -e "$entry" ] || continue
    ename="$(basename "$entry")"
    etarget="$DEST/.config/$ename"
    if [ -L "$etarget" ] && [ "$(readlink "$etarget")" = "$entry" ]; then
      continue
    fi
    backup "$etarget"
    echo "Symlinking $entry to $etarget..."
    ln -s "$entry" "$etarget"
  done
fi

# .cursor: copy contents instead of symlinking. ~/.cursor is a mountpoint;
# replacing it with a symlink fails with "file exists".
if [ -d "$REPO_DIR/.cursor" ]; then
  mkdir -p "$DEST/.cursor"
  echo "Copying $REPO_DIR/.cursor/ into $DEST/.cursor/..."
  cp -R "$REPO_DIR/.cursor/." "$DEST/.cursor/"
fi

# Symlink every skill shipped in this repo into the shared Agent Skills root,
# Claude Code's personal skill root, and Cursor's native personal skill root.
# Code stays version-controlled here; per-machine data/config lives outside.
if [ -d "$REPO_DIR/skills" ]; then
  for skills_root in "$DEST/.agents/skills" "$DEST/.claude/skills" "$DEST/.cursor/skills"; do
    mkdir -p "$skills_root"
    for skill in "$REPO_DIR"/skills/*/; do
      sname="$(basename "$skill")"
      starget="$skills_root/$sname"
      if [ -L "$starget" ] && [ "$(readlink "$starget")" = "${skill%/}" ]; then
        continue
      fi
      backup "$starget"
      echo "Symlinking skill $sname into $starget..."
      ln -s "${skill%/}" "$starget"
    done
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
