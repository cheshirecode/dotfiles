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

# ~/.bashrc is a machine-local stub that sources the tracked .bashrc, not a
# symlink to it. The Coder template appends its own blocks with
# `cat >> ~/.bashrc`; through a symlink that append lands in the tracked file.
# Measured 2026-10-01: 46 template lines, employer-named, sat uncommitted in the
# clone's .bashrc. The stub takes the append and the checkout stays clean.
BASHRC_MARK='# dotfiles install.sh: sources the tracked .bashrc. Lines below are machine-local.'

# Print what was appended to a tracked dotfile at a checkout's root. Fails unless
# the file is HEAD's copy plus a tail, so an edit to tracked lines is never
# carried off.
tracked_tail() {  # <path to a tracked dotfile>
  local f="$1" repo size rev
  repo="$(cd "$(dirname "$f")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 1
  rev="HEAD:$(basename "$f")"
  size="$(git -C "$repo" cat-file -s "$rev" 2>/dev/null)" || return 1
  cmp -s -n "$size" <(git -C "$repo" show "$rev") "$f" || return 1
  tail -c +"$((size + 1))" "$f"
}

install_bashrc_stub() {
  local rc="$DEST/.bashrc" src=". \"$REPO_DIR/.bashrc\"" tmp="$DEST/.bashrc.dotfiles-tmp.$$" real tail_
  if [ -f "$rc" ] && [ ! -L "$rc" ] && [ "$(head -n 1 "$rc")" = "$BASHRC_MARK" ]; then
    [ "$(sed -n 2p "$rc")" = "$src" ] && return 0
    # The checkout moved: repoint the source line, keep every machine-local line.
    { echo "$BASHRC_MARK"; echo "$src"; tail -n +3 "$rc"; } > "$tmp" && mv -f "$tmp" "$rc" &&
      echo "Repointed $rc at $REPO_DIR/.bashrc"
    return 0
  fi
  tail_=""
  if [ -L "$rc" ]; then
    real="$(readlink -f "$rc" 2>/dev/null)" || real=""
    if [ -n "$real" ] && tail_="$(tracked_tail "$real")" && [ -n "$tail_" ]; then
      # A pure append to a tracked file: move it into the stub, then put the
      # tracked file back to HEAD. Nothing else in that checkout is touched.
      { echo "$BASHRC_MARK"; echo "$src"; printf '%s\n' "$tail_"; } > "$tmp" && mv -f "$tmp" "$rc" &&
        git -C "$(dirname "$real")" checkout -- "$(basename "$real")" &&
        echo "Moved ${#tail_} appended bytes from $real into $rc"
      return 0
    fi
  elif [ -e "$rc" ]; then
    backup "$rc"
  fi
  { echo "$BASHRC_MARK"; echo "$src"; } > "$tmp" && mv -f "$tmp" "$rc" && echo "Wrote $rc (sources $REPO_DIR/.bashrc)"
}
install_bashrc_stub || echo "warning: could not write the ~/.bashrc stub" >&2

# ~/.gitconfig likewise: a machine-local stub that includes the tracked file.
# The Coder template runs `git config --global user.*` at start, and through a
# symlink that wrote a work identity into the tracked .gitconfig. Measured
# 2026-10-02: [user] with an employer email appended to the public file, and
# placed after every include, so it overrode the per-remote identity rules and
# this repo itself would have committed as the work account. The empty [user]
# comes first: git fills that existing section, above the include, so the
# tracked rules and ~/.gitconfig.local still decide and the template's identity
# only applies where nothing else sets one.
GITCONFIG_MARK='# dotfiles install.sh: includes the tracked .gitconfig. Lines below are machine-local.'
install_gitconfig_stub() {
  local rc="$DEST/.gitconfig" tmp="$DEST/.gitconfig.dotfiles-tmp.$$" want="$REPO_DIR/.gitconfig" real tail_ old k v
  if [ -f "$rc" ] && [ ! -L "$rc" ] && [ "$(head -n 1 "$rc")" = "$GITCONFIG_MARK" ]; then
    git config --file "$rc" --get-all include.path | grep -qxF "$want" && return 0
    old="$(git config --file "$rc" --get-all include.path | grep '/\.gitconfig$' | head -n 1)"
    [ -n "$old" ] || return 0
    git config --file "$rc" --replace-all include.path "$want" "^$(printf '%s' "$old" | sed 's/[][\.*^$/]/\\&/g')\$" &&
      echo "Repointed $rc at $want"
    return 0
  fi
  {
    echo "$GITCONFIG_MARK"
    echo "# The empty [user] below comes first on purpose: git config --global user.* fills"
    echo "# it, above the include, so the tracked rules still decide identity."
    echo "[user]"
    echo "[include]"
    printf '\tpath = %s\n' "$want"
  } > "$tmp" || return 1
  tail_=""
  if [ -L "$rc" ]; then
    real="$(readlink -f "$rc" 2>/dev/null)" || real=""
    if [ -n "$real" ] && tail_="$(tracked_tail "$real")" && [ -n "$tail_" ]; then
      # Re-apply key by key, so a carried [user] lands in the leading section
      # instead of after the include where it would override everything.
      printf '%s\n' "$tail_" > "$tmp.tail"
      git config --file "$tmp.tail" --list | while IFS='=' read -r k v; do
        git config --file "$tmp" --add "$k" "$v"
      done
      rm -f "$tmp.tail"
      mv -f "$tmp" "$rc" && git -C "$(dirname "$real")" checkout -- "$(basename "$real")" &&
        echo "Moved settings appended to $real into $rc"
      return 0
    fi
  elif [ -e "$rc" ]; then
    backup "$rc"
  fi
  mv -f "$tmp" "$rc" && echo "Wrote $rc (includes $want)"
}
install_gitconfig_stub || echo "warning: could not write the ~/.gitconfig stub" >&2

# One checkout, not two. Coder clones this repo into its own directory on a new
# instance, while the working checkout lives on the persistent volume, and every
# skill and shell link then resolves into the Coder clone: an edit in the working
# checkout does not reach a session until both are pulled. When the clone is
# clean and the primary already holds its commit, replace the clone with a
# symlink to the primary and finish the install from there. Anything else leaves
# the clone in place and says why.
# The clone is recognised by where it lives (a checkout under ~/.config, which
# is where Coder clones), not by its directory name.
PRIMARY_DIR="${DOTFILES_PRIMARY:-/workspace/dotfiles}"
CODER_CLONE_DIR="$REPO_DIR"
config_real="$(cd "$HOME/.config" 2>/dev/null && pwd -P)" || config_real=""
primary_real="$(cd "$PRIMARY_DIR" 2>/dev/null && pwd -P)" || primary_real=""
if [ -z "${DOTFILES_DEDUPED:-}" ] && [ -n "$config_real" ] && [ "${REPO_DIR#"$config_real"/}" != "$REPO_DIR" ] &&
   [ -d "$PRIMARY_DIR/.git" ] && [ "$primary_real" != "$REPO_DIR" ]; then
  why=""
  head_="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)" || why="cannot read the clone's HEAD"
  [ -z "$why" ] && [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ] && why="the clone has uncommitted changes"
  [ -z "$why" ] && ! git -C "$PRIMARY_DIR" cat-file -e "$head_^{commit}" 2>/dev/null && why="$PRIMARY_DIR lacks the clone's commit ${head_:0:7}"
  if [ -n "$why" ]; then
    echo "Keeping $CODER_CLONE_DIR as a separate clone: $why." >&2
  else
    moved="$CODER_CLONE_DIR.bak-$(date +%Y%m%d%H%M%S)"
    if mv "$CODER_CLONE_DIR" "$moved" && ln -s "$PRIMARY_DIR" "$CODER_CLONE_DIR"; then
      echo "Replaced the clone with a link to $PRIMARY_DIR (old clone at $moved)"
      exec env DOTFILES_DEDUPED=1 bash "$PRIMARY_DIR/install.sh" "$@"
    fi
    echo "warning: could not replace $CODER_CLONE_DIR with a link; continuing from the clone." >&2
    [ -e "$CODER_CLONE_DIR" ] || mv "$moved" "$CODER_CLONE_DIR"
  fi
fi

# Symlink top-level dotfiles (anything matching .* except VCS/meta dirs).
for src in "$REPO_DIR"/.*; do
  name="$(basename "$src")"
  case "$name" in
    .|..|.git|.github|.gitignore) continue ;;
    .cursor) continue ;; # handled below
    .bashrc) continue ;; # a machine-local stub, written above
    .gitconfig) continue ;; # a machine-local stub, written above
    .claude) continue ;; # real Claude home in $DEST: settings, transcripts, memory. The repo's copy is gitignored scratch; linking it over ~/.claude destroys the user's.
    .config) continue ;; # handled below — repo lives under ~/.config, symlinking it wholesale creates a self-referential loop
    .shell_common.*) continue ;; # machine-local overlays; see .gitignore. The repo must never supply one, so never link one out of it.
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
  # .profile, .zshrc, the skills links and terminfo never ran, and
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
# a directory under ~/.config, so symlinking ~/.config at the top level would
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
    # step after this loop (skills, .gitconfig.local) never ran.
    if mountpoint -q "$etarget" 2>/dev/null; then
      echo "Copying $entry/ into mountpoint $etarget/..."
      cp -R "$entry/." "$etarget/"
      continue
    fi
    # Second call site for the guard above. This loop was unwired: it called
    # backup() and ln -sfn directly, so a real ~/.config/opencode was moved
    # aside and the repo directory linked over it, taking 11 local items out
    # of the live path (reported 2026-09-16). The mountpoint branch above
    # covers the Coder case; this covers a plain directory.
    if holds_user_data "$etarget"; then
      echo "warning: $etarget is a non-empty real directory; refusing to replace it with a symlink." >&2
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
  # Guarded: cp cannot write through a dangling
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

# Bootstrap ~/.gitconfig.local (machine-local identity, untracked). The
# committed .gitconfig pulls it in via [include]; without it, git complains
# about a missing include path on every invocation.
#
# Posture: the fallback identity is the PERSONAL one, seeded from the tracked
# .gitconfig.cheshireCode so the identity has one copy in the repo, not two.
# Any other identity — work or otherwise — is declared by that tree's .envrc
# (direnv walks up to the nearest one; see .envrc.example), never here.
seed_local_gitconfig() {
  seed_name="$(git config -f "$REPO_DIR/.gitconfig.cheshireCode" user.name 2>/dev/null || true)"
  seed_email="$(git config -f "$REPO_DIR/.gitconfig.cheshireCode" user.email 2>/dev/null || true)"
  if [ -n "$seed_name" ] && [ -n "$seed_email" ]; then
    cat > "$DEST/.gitconfig.local" <<EOF
# Per-machine git identity fallback: the PERSONAL identity, seeded from the
# repo's tracked .gitconfig.cheshireCode. Do not commit this file. Any other
# identity — work or otherwise — is declared by that tree's own .envrc
# (GIT_AUTHOR_* + GIT_COMMITTER_* + WORKLOG_IDENTITY_DOMAIN); direnv loads
# the nearest .envrc walking up from the cwd, and a child .envrc must
# source_up to inherit the tree default. A checkout with no .envrc on its
# walk-up path commits personal by design.
[user]
	name = $seed_name
	email = $seed_email
EOF
  else
    echo "warning: could not read user.name/user.email from $REPO_DIR/.gitconfig.cheshireCode; seeding an empty template — fill in [user] or commits fall back to git's machine default." >&2
    cat > "$DEST/.gitconfig.local" <<'EOF'
# Per-machine git identity. Add a [user] block here; do not commit this file.
[user]
	# name = Your Name
	# email = you@example.com
EOF
  fi
}

# Upgrade a seed left by the empty-template era to the personal fallback.
# Exact match against that template only: a file the machine has edited
# carries its own identity decisions and is not ours to replace.
old_local_seed='# Per-machine git identity. Add a [user] block here; do not commit this file.
[user]
	# name = Your Name
	# email = you@example.com'
if [ -e "$DEST/.gitconfig.local" ] \
   && [ "$(cat "$DEST/.gitconfig.local")" = "$old_local_seed" ]; then
  echo "Upgrading untouched $DEST/.gitconfig.local to the personal-fallback seed..."
  seed_local_gitconfig
fi

if [ ! -e "$DEST/.gitconfig.local" ]; then
  echo "Creating $DEST/.gitconfig.local — personal fallback identity."
  seed_local_gitconfig
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

# Machine-local helpers belong in this file, not in the repo. Anything you
# would have put in a ~/.shell_common.<suffix> overlay goes here: the repo no
# longer tracks or supplies one. Credentials go in ~/.env.secrets instead.

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

# Bootstrap ~/.env.secrets (machine-local credentials, untracked). This is the
# one format for every credential on every machine: dotenv KEY=value, mode
# 0600, generated empty, filled in by hand per host. It follows the pattern
# Coder documents for workspace secrets -- a persistent file the user writes
# after the workspace is built -- because a dotfiles repo cannot carry values
# that differ per machine, and must never carry values at all.
#
# Guarded on absence like the two bootstraps above: a re-run must not clobber
# a file you already filled in. The installer only ever writes empty keys.
if [ ! -e "$DEST/.env.secrets" ]; then
  # Absent template and successful copy are different outcomes, and a silent
  # skip would read like a pass on a clone whose template failed to check out.
  if [ -r "$REPO_DIR/templates/env.secrets.example" ]; then
    echo "Creating $DEST/.env.secrets — fill in the keys for this machine."
    cp "$REPO_DIR/templates/env.secrets.example" "$DEST/.env.secrets"
    chmod 600 "$DEST/.env.secrets"
  else
    echo "warning: templates/env.secrets.example is missing; did not create $DEST/.env.secrets." >&2
  fi
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

# Runtime deps bin/doctor.sh requires. On a Coder workspace /usr is the image
# overlay, so an apt install is lost on every rebuild and a new instance comes
# up without them. Measured 2026-10-01: direnv, rg and gh were missing on a new
# instance and three suite checks failed until they were installed by hand.
# zsh and shellcheck are suite tools: without them tests/run.sh skips the
# lint lanes and the zsh welcome check, and still reports green.
# Coder only (CODER_WORKSPACE_ID): CI and laptops manage their own packages.
# Missing tools are reported either way; nothing here aborts the installer.
if [ -n "${CODER_WORKSPACE_ID:-}" ] && [ -z "${DOTFILES_NO_APT:-}" ]; then
  (
    set +e
    missing=() pkgs=()
    for pair in python3:python3 gh:gh git:git rg:ripgrep jq:jq direnv:direnv zsh:zsh shellcheck:shellcheck; do
      command -v "${pair%%:*}" >/dev/null 2>&1 || { missing+=("${pair%%:*}"); pkgs+=("${pair#*:}"); }
    done
    [ "${#pkgs[@]}" -eq 0 ] && exit 0
    if command -v apt-get >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      echo "Installing missing runtime deps: ${missing[*]}"
      sudo -n apt-get install -y -qq "${pkgs[@]}" >/dev/null 2>&1 ||
        { sudo -n apt-get update -qq >/dev/null 2>&1 && sudo -n apt-get install -y -qq "${pkgs[@]}" >/dev/null 2>&1; }
      still=()
      for t in "${missing[@]}"; do command -v "$t" >/dev/null 2>&1 || still+=("$t"); done
      [ "${#still[@]}" -eq 0 ] || echo "warning: still missing after apt: ${still[*]}" >&2
    else
      echo "warning: missing runtime deps (no apt-get or no passwordless sudo): ${missing[*]}" >&2
    fi
  ) || true
fi

echo "Dotfiles installation complete."
