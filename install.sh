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
    # Some ~/.config children are persistent-disk mountpoints on this workspace
    # template (e.g. opencode). They cannot be moved aside or replaced by a
    # symlink — mv fails with EBUSY — so copy into them like .cursor below.
    # Without this the whole installer aborted here under `set -eu`, and every
    # step after this loop (skills, super-ruler, .gitconfig.local) never ran.
    if mountpoint -q "$etarget" 2>/dev/null; then
      echo "Copying $entry/ into mountpoint $etarget/..."
      cp -R "$entry/." "$etarget/"
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

# super-ruler: clone (or fast-forward) the shared skills repo, then run its own
# installer, which copies .ruler/skills/*/SKILL.md into ~/.claude/commands/ as
# /skill-name for every repo. This is the install path super-ruler's README
# prescribes for dotfiles; without it the workspace keeps whatever stale copy
# ~/.claude/commands happened to hold and silently drifts behind master.
#
# Non-fatal by design: a network failure or a broken upstream installer must not
# abort the rest of dotfiles installation, so the whole block is guarded.
SUPER_RULER_DIR="${SUPER_RULER_DIR:-/workspace/super-ruler}"
if [ "${SKIP_SUPER_RULER:-0}" != "1" ]; then
  (
    set +e
    if [ -d "$SUPER_RULER_DIR/.git" ]; then
      echo "Updating super-ruler in $SUPER_RULER_DIR..."
      git -C "$SUPER_RULER_DIR" fetch --quiet origin master &&
        git -C "$SUPER_RULER_DIR" merge --ff-only --quiet origin/master ||
        echo "super-ruler: fast-forward skipped (local commits or fetch failed); using current checkout." >&2
    else
      echo "Cloning super-ruler into $SUPER_RULER_DIR..."
      mkdir -p "$(dirname "$SUPER_RULER_DIR")"
      git clone --quiet https://gitlab.com/textemma/super-ruler.git "$SUPER_RULER_DIR" ||
        echo "super-ruler: clone failed; skills not installed." >&2
    fi

    # Prune commands whose upstream skill no longer exists (renames and splits
    # leave the old name behind, and a stale duplicate still shows up as a
    # slash command). Only touch names super-ruler itself once owned.
    if [ -d "$SUPER_RULER_DIR/.ruler/skills" ] && [ -d "$DEST/.claude/commands" ]; then
      for cmd in "$DEST"/.claude/commands/*.md; do
        [ -e "$cmd" ] || continue
        cname="$(basename "$cmd" .md)"
        [ -d "$SUPER_RULER_DIR/.ruler/skills/$cname" ] && continue
        if git -C "$SUPER_RULER_DIR" log --diff-filter=D --format=%H -1 \
             -- ".ruler/skills/$cname/SKILL.md" 2>/dev/null | grep -q .; then
          echo "Removing stale super-ruler command $cname (deleted upstream)..."
          rm -f "$cmd"
        fi
      done
    fi

    [ -x "$SUPER_RULER_DIR/install.sh" ] && "$SUPER_RULER_DIR/install.sh"
  ) || echo "super-ruler: setup skipped (non-fatal)." >&2
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
