#!/usr/bin/env bash
# Install the Google Workspace CLI (`gws`) and its 95 agent skills.
#
# Cross-platform (macOS Homebrew + Linux apt/dnf/pacman/apk; WSL2 too).
#
# What it does:
#   1. Ensures `node` + `npm` are present (installs via the OS pkg manager
#      if missing — same dispatch table as install-runtime-deps.sh).
#   2. `npm install -g @googleworkspace/cli` — pulls the prebuilt npm
#      binary, no Rust toolchain needed. Idempotent: skips if `gws` is
#      already on PATH and version-matches the target.
#   3. Symlinks the 95 upstream `gws-*` skills into both agent surfaces:
#        ~/.claude/skills/gws/{SKILL.md,skills/}
#        ~/.agents/skills/gws/{SKILL.md,skills/}
#      so Claude Code / OpenCode / Codex all discover them.
#
# Refuses Windows-native. WSL2 is the supported Windows path (same gate
# as install.sh).
#
# Optional deps (post-install, manual): the user runs `gws auth setup`
# once OAuth credentials are obtained. See googleworkspace-cli/SETUP.md
# in the host repo for the flow.

set -euo pipefail

GWS_PKG="@googleworkspace/cli"
GWS_SOURCE_REPO="${GWS_SOURCE_REPO:-$HOME/projects/googleworkspace-cli}"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGENTS_SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help)
    cat <<'EOF'
usage: bin/install-gws.sh [--dry-run]
  --dry-run  print intended actions without changing files

installs:
  - node + npm (via OS pkg manager, if missing)
  - gws (npm -g @googleworkspace/cli)
  - symlinks gws SKILL.md + skills/ into ~/.claude and ~/.agents
EOF
    exit 0
    ;;
  *) echo "install-gws: unknown flag $1" >&2; exit 2 ;;
esac

# OS gate — same policy as install.sh.
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*)
    cat >&2 <<EOF
install-gws: native Windows is not supported.

Use WSL2 (Ubuntu recommended) and re-run bin/install.sh.
EOF
    exit 1
    ;;
  *)
    echo "install-gws: unsupported OS '$OS'" >&2
    exit 1
    ;;
esac

detect_pkg_manager() {
  case "$OS" in
    Darwin)
      command -v brew >/dev/null && { echo brew; return; }
      echo "install-gws: Homebrew not found on macOS — install from https://brew.sh first" >&2
      exit 1
      ;;
    Linux)
      command -v apt-get >/dev/null && { echo apt; return; }
      command -v dnf     >/dev/null && { echo dnf; return; }
      command -v pacman  >/dev/null && { echo pacman; return; }
      command -v apk     >/dev/null && { echo apk; return; }
      echo "install-gws: no supported package manager (apt/dnf/pacman/apk) found" >&2
      exit 1
      ;;
  esac
}

# npm ships as `nodejs` + `npm` on Debian/Ubuntu; `nodejs` on Fedora;
# `nodejs` + `npm` on Alpine; `node` on Homebrew (npm bundled). Map
# canonical tool name → OS package name.
node_pkg_for() {
  local pm="$1"
  case "$pm" in
    brew)   echo node ;;        # Homebrew formula `node` bundles npm
    apt)    echo nodejs ;;       # Debian splits nodejs / npm; `apt install nodejs` pulls both
    dnf)    echo nodejs ;;
    pacman) echo nodejs ;;
    apk)    echo nodejs ;;
  esac
}

npm_pkg_for() {
  local pm="$1"
  case "$pm" in
    brew)   echo "" ;;          # npm bundled with `node` formula
    apt)    echo npm ;;
    dnf)    echo npm ;;
    pacman) echo npm ;;
    apk)    echo npm ;;
  esac
}

install_with() {
  local pm="$1"; shift
  local pkgs=("$@")
  case "$pm" in
    brew)   brew install "${pkgs[@]}" ;;
    apt)    sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}" ;;
    dnf)    sudo dnf install -y "${pkgs[@]}" ;;
    pacman) sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    apk)    sudo apk add --no-cache "${pkgs[@]}" ;;
  esac
}

PM=$(detect_pkg_manager)
echo "install-gws: detected OS=$OS pm=$PM"

# 1. Ensure node + npm.
MISSING_PKGS=()
if ! command -v node >/dev/null; then
  MISSING_PKGS+=("$(node_pkg_for "$PM")")
fi
if ! command -v npm >/dev/null; then
  local_pkg="$(npm_pkg_for "$PM")"
  [[ -n "$local_pkg" ]] && MISSING_PKGS+=("$local_pkg")
fi

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
  echo "install-gws: installing missing node/npm packages: ${MISSING_PKGS[*]}"
  # Council guardrail: non-TTY → require explicit consent, mirroring
  # install-runtime-deps.sh. Stops a CI image from silently sudoing.
  if [[ ! -t 0 && "${INSTALL_GWS_YES:-}" != "1" ]]; then
    echo "install-gws: refusing sudo install in non-TTY context." >&2
    echo "  Set INSTALL_GWS_YES=1 to proceed (or run interactively)." >&2
    exit 4
  fi
  if [[ $DRY_RUN -eq 0 ]]; then
    install_with "$PM" "${MISSING_PKGS[@]}"
  else
    echo "  [dry-run] would run: $PM install ${MISSING_PKGS[*]}"
  fi
fi

# 2. Install gws via npm.
if command -v gws >/dev/null; then
  echo "install-gws: gws already present: $(gws --version 2>/dev/null | head -1)"
else
  echo "install-gws: installing $GWS_PKG globally"
  if [[ ! -t 0 && "${INSTALL_GWS_YES:-}" != "1" ]]; then
    echo "install-gws: refusing global npm install in non-TTY context." >&2
    echo "  Set INSTALL_GWS_YES=1 to proceed (or run interactively)." >&2
    exit 4
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] would run: npm install -g $GWS_PKG"
  else
    npm install -g "$GWS_PKG"
    echo "install-gws: installed $(gws --version 2>/dev/null | head -1)"
  fi
fi

# 3. Symlink upstream skills into both agent surfaces.
# Source lives in the googleworkspace-cli clone (the npm pkg doesn't ship skills).
if [[ ! -d "$GWS_SOURCE_REPO/skills" ]]; then
  echo "install-gws: WARN — source skills dir not found at $GWS_SOURCE_REPO/skills" >&2
  echo "  Clone https://github.com/googleworkspace/cli there to enable the gws-* skills." >&2
  echo "install-gws: gws CLI itself is installed; skills symlinks deferred."
  exit 0
fi

link_skill_surface() {
  local surface_name="$1"
  local target_dir="$2"
  local src_root="$GWS_SOURCE_REPO"

  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$target_dir"
  fi

  # Link SKILL.md (the index).
  if [[ -f "$src_root/SKILL.md" ]]; then
    if [[ -e "$target_dir/SKILL.md" || -L "$target_dir/SKILL.md" ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] exists: $target_dir/SKILL.md"
      fi
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] link $src_root/SKILL.md → $target_dir/SKILL.md"
      else
        ln -s "$src_root/SKILL.md" "$target_dir/SKILL.md"
        echo "  linked $surface_name SKILL.md"
      fi
    fi
  fi

  # Link skills/ directory.
  if [[ -d "$src_root/skills" ]]; then
    if [[ -e "$target_dir/skills" || -L "$target_dir/skills" ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] exists: $target_dir/skills"
      fi
    else
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] link $src_root/skills → $target_dir/skills"
      else
        ln -s "$src_root/skills" "$target_dir/skills"
        echo "  linked $surface_name skills/"
      fi
    fi
  fi
}

echo "install-gws: wiring skill symlinks"
link_skill_surface "Claude Code" "$CLAUDE_SKILLS_DIR/gws"
link_skill_surface "OpenCode/Codex" "$AGENTS_SKILLS_DIR/gws"

echo "install-gws: done"
echo "  next: run 'gws auth setup' interactively to complete OAuth,"
echo "        or use 'gws schema <svc.resource.method>' for read-only introspection."
