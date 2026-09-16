#!/usr/bin/env bash
# Custom installer for `coder dotfiles`. Replicates the default symlink
# behavior for top-level dotfiles, but copies .cursor into the destination
# instead of symlinking because ~/.cursor is a persistent-disk mountpoint
# on this workspace template (symlink-over-mountpoint fails).
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DEST="${CODER_SYMLINK_DIR:-$HOME}"

# A real, non-empty directory in $DEST is user data, not a stale dotfile. On the
# Coder template these are persistent-disk mountpoints and mv fails EBUSY, so
# backup() only warned and the hazard stayed invisible; on a laptop $HOME is a
# plain directory and the mv succeeds. Reported 2026-09-16: ~/.claude (settings,
# transcripts, per-project memory) was moved to ~/.claude.bak and the repo's
# gitignored .claude/ linked in its place. The skip list below names .claude,
# but a name list only ever covers what someone remembered; this covers the next
# directory added to the repo.
holds_user_data() {
  local target="$1"
  [ -d "$target" ] && [ ! -L "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]
}

backup() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if mv "$target" "$target.bak"; then
      echo "Moved $target to $target.bak..."
    else
      # Non-fatal: an unmovable target (mountpoint, EBUSY) must not abort the
      # installer. The ln -sfn calls below replace it in place instead.
      echo "warning: could not back up $target; leaving it in place." >&2
    fi
  fi
}

# Symlink top-level dotfiles (anything matching .* except VCS/meta dirs).
for src in "$REPO_DIR"/.*; do
  name="$(basename "$src")"
  case "$name" in
    .|..|.git|.github|.gitignore) continue ;;
    .cursor) continue ;; # handled below
    .claude) continue ;; # real Claude home in $DEST: settings, transcripts, memory. The repo's copy is gitignored scratch; linking it over ~/.claude destroys the user's.
    .config) continue ;; # handled below — repo lives under ~/.config, symlinking it wholesale creates a self-referential loop
    .envrc.github) continue ;; # gitignored secret holder, sourced explicitly
  esac
  target="$DEST/$name"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
    continue
  fi
  if holds_user_data "$target"; then
    echo "warning: $target is a non-empty real directory; refusing to replace it with a symlink." >&2
    continue
  fi
  backup "$target"
  echo "Symlinking $src to $target..."
  # -f because a concurrent writer can recreate $target in the window between
  # backup() and here. Coder runs its own bashrc-appender script
  # (`cat >> $HOME/.bashrc`) in PARALLEL with `coder dotfiles`; on 2026-09-04 it
  # recreated ~/.bashrc ~1ms after the mv, plain `ln -s` failed EEXIST, and
  # `set -e` aborted the whole installer on its second file -- so .shell_common,
  # .profile, .zshrc, the skills links, super-ruler and terminfo never ran, and
  # the shell silently came up with none of these dotfiles loaded.
  # -n so a symlinked-directory target is replaced rather than written through.
  ln -sfn "$src" "$target" || echo "warning: could not link $target; skipping." >&2
done

# Prune links left by an older checkout. The loop above only creates links for
# entries the repo still has, so a link whose target moved or was deleted stays
# dangling forever and the shell silently loads nothing. Reported 2026-09-16:
# after the checkout moved, all 11 top-level links pointed into a deleted
# directory, and ~/.zshenv and ~/.gitignore stayed dangling even after a repair
# run because this repo ships neither file.
#
# Deliberately narrow: only a dangling link whose target path lies under a
# dotfiles checkout. A dangling link to anything else belongs to the user or to
# another tool, and removing it is not this installer's business.
for link in "$DEST"/.*; do
  name="$(basename "$link")"
  case "$name" in .|..) continue ;; esac
  [ -L "$link" ] || continue
  [ -e "$link" ] && continue
  case "$(readlink "$link")" in
    */dotfiles/*|*/dotfiles)
      echo "Removing dangling $name (target gone from a dotfiles checkout)..."
      rm -f "$link"
      ;;
  esac
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
    ln -sfn "$entry" "$etarget" || echo "warning: could not link $etarget; skipping." >&2
  done
fi

# .cursor: copy contents instead of symlinking. ~/.cursor is a mountpoint;
# replacing it with a symlink fails with "file exists".
if [ -d "$REPO_DIR/.cursor" ]; then
  # Guarded like the super-ruler block below: cp cannot write through a dangling
  # symlink, and unguarded under `set -eu` that aborted the whole installer.
  # Reported 2026-09-16: ~/.cursor/rules and ~/.cursor/mcp.json pointed into a
  # deleted checkout, cp failed "Not a directory" / "Permission denied", and the
  # skills links, the ~/.gitconfig.local and ~/.shell_common.local bootstraps
  # and the terminfo entry never ran.
  (
    set +e
    mkdir -p "$DEST/.cursor"
    # Clear destination links whose target is gone; they are leftovers from an
    # older checkout and cp would fail writing through them.
    for stale in "$DEST/.cursor"/* "$DEST/.cursor"/.*; do
      case "$(basename "$stale")" in .|..) continue ;; esac
      if [ -L "$stale" ] && [ ! -e "$stale" ]; then
        echo "Removing dangling $stale (target gone)..."
        rm -f "$stale"
      fi
    done
    echo "Copying $REPO_DIR/.cursor/ into $DEST/.cursor/..."
    cp -R "$REPO_DIR/.cursor/." "$DEST/.cursor/" ||
      echo "warning: could not copy .cursor into $DEST; continuing." >&2
  ) || true
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
      ln -sfn "${skill%/}" "$starget" || echo "warning: could not link $starget; skipping." >&2
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
      git clone --quiet <external-skills-repo> "$SUPER_RULER_DIR" ||
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

    # super-ruler's installer writes to $HOME/.claude/commands unconditionally.
    # Point HOME at $DEST so it agrees with the prune loop above, which a test
    # harness or a template installing outside $HOME would otherwise split.
    [ -x "$SUPER_RULER_DIR/install.sh" ] && HOME="$DEST" "$SUPER_RULER_DIR/install.sh"
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

# Bootstrap ~/.shell_common.local (machine-local shell env, untracked). The
# committed .shell_common sources it; .bashrc also sources it above the
# interactive guard, so it applies to non-interactive shells too. Seeded with
# the Kubernetes unsets: this workspace runs as a k8s pod, so the kubelet
# injects KUBERNETES_* vars for the in-cluster API, and those make client-go
# prefer in-cluster config over ~/.kube/config, silently pointing kubectl and
# helm at the wrong API server. A no-op on a machine where they are not set.
if [ ! -e "$DEST/.shell_common.local" ]; then
  echo "Creating $DEST/.shell_common.local — machine-local shell env."
  cat > "$DEST/.shell_common.local" <<'SCLEOF'
# ~/.shell_common.local — machine-local shell env. NOT in the dotfiles repo.
# Sourced from .bashrc above the interactive guard, so this applies to
# non-interactive shells (bash -c from tools/hooks) as well.

# Vault helpers live in the tracked .shell_common.vault (symlinked into $HOME
# by this installer). Sourced here, not from ~/.shell_common, because that file
# is read below .bashrc's interactive guard and so is invisible to `bash -c`.
[ -r "$HOME/.shell_common.vault" ] && . "$HOME/.shell_common.vault"

# --- drop Kubernetes service-discovery injection ---------------------------
# Only meaningful when running as a k8s pod; a harmless no-op elsewhere.
unset KUBERNETES_SERVICE_HOST
unset KUBERNETES_SERVICE_PORT
unset KUBERNETES_SERVICE_PORT_HTTPS
unset KUBERNETES_PORT
unset KUBERNETES_PORT_443_TCP
unset KUBERNETES_PORT_443_TCP_ADDR
unset KUBERNETES_PORT_443_TCP_PORT
unset KUBERNETES_PORT_443_TCP_PROTO
SCLEOF
  chmod 600 "$DEST/.shell_common.local"
fi

# Install xterm-ghostty terminfo. ~/.terminfo sits on the ephemeral overlay
# (only /workspace and a few ~/.* dirs are on the persistent disk), so a
# rebuilt workspace loses it. Without this entry the session falls back to
# xterm-256color, which has no XF/XM/xm capabilities — so focus (1004) and
# SGR mouse (1003/1006) reporting enabled by a TUI can never be disabled and
# leaks into the prompt as ^[[I / ^[[O / ^[[<35;..M on every mouse click.
#
# Prefers a system copy of the entry; otherwise derives one from
# xterm-256color and adds the three missing capabilities. Non-fatal: a tic
# failure must not abort the installer, and .bashrc has a TERM fallback guard.
if ! infocmp xterm-ghostty >/dev/null 2>&1; then
  (
    set +e
    if command -v tic >/dev/null 2>&1; then
      echo "Installing xterm-ghostty terminfo into $DEST/.terminfo..."
      mkdir -p "$DEST/.terminfo"
      src=""
      for cand in /usr/share/terminfo /usr/lib/terminfo /etc/terminfo; do
        if [ -e "$cand/x/xterm-ghostty" ]; then src="$cand"; break; fi
      done
      if [ -n "$src" ]; then
        infocmp -x -A "$src" xterm-ghostty | tic -x -o "$DEST/.terminfo" - 2>/dev/null
      else
        {
          printf 'xterm-ghostty|ghostty|Ghostty,\n'
          printf '\tXF,\n'
          printf '\tXM=\\E[?1006;1000%%?%%p1%%{1}%%=%%th%%el%%;,\n'
          printf '\txm=\\E[<%%i%%p3%%d;%%p1%%d;%%p2%%d;%%?%%p4%%tM%%em%%;,\n'
          printf '\tuse=xterm-256color,\n'
        } | tic -x -o "$DEST/.terminfo" - 2>/dev/null
      fi
      if infocmp -x -A "$DEST/.terminfo" xterm-ghostty >/dev/null 2>&1; then
        echo "  xterm-ghostty terminfo installed."
      else
        echo "  xterm-ghostty terminfo install failed (non-fatal); .bashrc falls back to xterm-256color." >&2
      fi
    else
      echo "  tic not available; skipping xterm-ghostty terminfo." >&2
    fi
  ) || true
fi

# Install the overlay-repair hook onto the PERSISTENT volume. It is not
# symlinked into $HOME like the dotfiles above, because the path it is invoked
# from -- the SessionStart hook in ~/.claude/settings.json -- must keep working
# even when this clone is missing or install.sh aborted earlier (the clone is
# re-created every workspace start and has raced with the template's bashrc
# appender before). A copy on /workspace survives both.
#
# Copy only when the content differs, so a start that changes nothing says so.
# Non-fatal: /workspace may not be mounted (a plain container, CI), and that
# must not abort the installer.
HOOK_BIN_DIR="${HOOK_BIN_DIR:-/workspace/bin}"
if [ -d "$(dirname "$HOOK_BIN_DIR")" ] && [ -f "$REPO_DIR/bin/restore-home-links.sh" ]; then
  (
    set +e
    mkdir -p "$HOOK_BIN_DIR" 2>/dev/null
    hook_target="$HOOK_BIN_DIR/restore-home-links.sh"
    if ! cmp -s "$REPO_DIR/bin/restore-home-links.sh" "$hook_target"; then
      if cp "$REPO_DIR/bin/restore-home-links.sh" "$hook_target" 2>/dev/null; then
        chmod 0755 "$hook_target" 2>/dev/null
        echo "Installed restore-home-links.sh -> $hook_target"
      else
        echo "  warning: could not install $hook_target; keeping existing copy." >&2
      fi
    fi
  ) || true
fi

echo "Dotfiles installation complete."
