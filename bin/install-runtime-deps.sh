#!/usr/bin/env bash
# Install runtime dependencies the agent-skill bootstrap requires.
#
# Deps: python3 (≥3.10), gh, git, rg (ripgrep), jq, direnv.
# Optional: gcloud (only if you'll talk to BigQuery / GCP).
#
# Supports macOS (Homebrew) and Linux (apt / dnf / pacman / apk).
# Windows users: run inside WSL2 — native Windows is best-effort only.
#
# Idempotent. Re-running on a fully-installed machine is a no-op.

set -euo pipefail

REQUIRED=(python3 gh git rg jq direnv)
OPTIONAL=(gcloud)

detect_pkg_manager() {
  case "$(uname -s)" in
    Darwin)
      command -v brew >/dev/null && { echo brew; return; }
      echo "install-runtime-deps: Homebrew not found on macOS — install from https://brew.sh first" >&2
      exit 1
      ;;
    Linux)
      command -v apt-get >/dev/null && { echo apt; return; }
      command -v dnf     >/dev/null && { echo dnf; return; }
      command -v pacman  >/dev/null && { echo pacman; return; }
      command -v apk     >/dev/null && { echo apk; return; }
      echo "install-runtime-deps: no supported package manager (apt/dnf/pacman/apk) found" >&2
      exit 1
      ;;
    *)
      echo "install-runtime-deps: unsupported OS '$(uname -s)' — Mac+Linux+WSL2 only" >&2
      exit 1
      ;;
  esac
}

# Map our canonical names to per-package-manager package names.
pkg_for() {
  local tool="$1" pm="$2"
  case "$tool:$pm" in
    rg:brew|rg:dnf|rg:pacman) echo ripgrep ;;
    rg:apt) echo ripgrep ;;
    rg:apk) echo ripgrep ;;
    direnv:apt|direnv:dnf|direnv:pacman|direnv:apk) echo direnv ;;
    *) echo "$tool" ;;
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
echo "install-runtime-deps: detected package manager: $PM"

MISSING=()
for tool in "${REQUIRED[@]}"; do
  command -v "$tool" >/dev/null || MISSING+=("$(pkg_for "$tool" "$PM")")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "install-runtime-deps: all required tools present — nothing to do"
else
  echo "install-runtime-deps: installing: ${MISSING[*]}"
  install_with "$PM" "${MISSING[@]}"
fi

# Optional: tell the user what's missing but don't auto-install.
for tool in "${OPTIONAL[@]}"; do
  if ! command -v "$tool" >/dev/null; then
    echo "install-runtime-deps: optional tool '$tool' not installed (skip unless you need it)"
  fi
done

# Verify Python ≥ 3.10 — worklog's bin/_lint.py uses 3.10+ syntax.
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
  echo "install-runtime-deps: WARNING — python3 is older than 3.10. worklog protocol needs 3.10+." >&2
fi

echo "install-runtime-deps: done"
