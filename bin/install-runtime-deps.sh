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
  # Council guardrail: non-TTY → require explicit --yes. Stops a CI image
  # from silently installing packages it didn't intend to consent to.
  if [[ ! -t 0 && "${INSTALL_RUNTIME_DEPS_YES:-}" != "1" ]]; then
    echo "install-runtime-deps: refusing sudo install in non-TTY context." >&2
    echo "  Set INSTALL_RUNTIME_DEPS_YES=1 to proceed (or run interactively)." >&2
    exit 4
  fi
  install_with "$PM" "${MISSING[@]}"
fi

# Optional: tell the user what's missing but don't auto-install.
for tool in "${OPTIONAL[@]}"; do
  if ! command -v "$tool" >/dev/null; then
    echo "install-runtime-deps: optional tool '$tool' not installed (skip unless you need it)"
  fi
done

# Council guardrail #11: Python <3.10 is a hard fail, not a warning.
# Downstream worklog lint dies far from the cause when 3.10+ syntax is missing.
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
  PYVER=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || echo "?")
  echo "install-runtime-deps: FAIL — python3 is $PYVER, need ≥3.10." >&2
  echo "  Remediation: pyenv install 3.11 && pyenv global 3.11   (macOS/Linux)" >&2
  echo "              brew install python@3.11                   (macOS)" >&2
  exit 1
fi

# Council guardrail (NICE): minimum-version assertions for gh + git.
# Old `gh` has incompatible flags that surface as cryptic install-skills failures.
check_min_version() {
  local tool="$1" min="$2" current
  current=$("$tool" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 0)
  printf '%s\n%s\n' "$min" "$current" | sort -V -C 2>/dev/null && return 0
  echo "install-runtime-deps: WARN — $tool $current is older than $min (some features may fail)" >&2
}
command -v gh  >/dev/null && check_min_version gh  2.40 || true
command -v git >/dev/null && check_min_version git 2.30 || true

echo "install-runtime-deps: done"
