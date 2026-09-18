#!/usr/bin/env bash
# Install or upgrade the browser-use CLI (uv-managed, Python 3.12) and
# register its vendor skill with every harness on this machine.
#
# Cross-platform: macOS and Linux. Windows must go through WSL.
# Sandbox-safe: UV_TOOL_DIR / UV_TOOL_BIN_DIR / HOME are honored throughout,
# so pointing them at a scratch tree installs without touching the host.
#
# Usage: install-browser-use.sh [--bootstrap-uv] [--no-skill] [--strict-doctor]
set -uo pipefail

PY="3.12"
PACKAGE="browser-use"
BOOTSTRAP_UV=0
NO_SKILL=0
STRICT_DOCTOR=0

usage() {
  cat <<'USAGE'
Usage: install-browser-use.sh [flags]

Install or upgrade the browser-use CLI to the latest stable release with uv
using Python 3.12, then register its vendor skill (browser-use skill install)
and run a connection doctor.

Flags:
  --bootstrap-uv   Install uv via the official astral.sh installer when missing
                   (default: refuse with exit 2 and print the manual step)
  --no-skill       Skip `browser-use skill install`
  --strict-doctor  Exit nonzero when the post-install doctor is unhealthy
  -h, --help       Show this help

Environment (sandbox-safe):
  UV_TOOL_DIR / UV_TOOL_BIN_DIR  uv tool install + bin locations
  HOME                           skill-registration + config root
  BH_HOME / BROWSER_HARNESS_HOME browser-harness state root
USAGE
}

log() { printf '%s\n' "==> $*"; }
warn() { printf '%s\n' "WARN: $*" >&2; }
die() { printf '%s\n' "ERROR: $*" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --bootstrap-uv) BOOTSTRAP_UV=1 ;;
    --no-skill) NO_SKILL=1 ;;
    --strict-doctor) STRICT_DOCTOR=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown flag: $1" 2 ;;
  esac
  shift
done

# --- OS gate ---------------------------------------------------------------
fake_os="${BU_SETUP_FAKE_OS:-$(uname -s)}"
case "$fake_os" in
  Darwin|Linux) ;;
  *)
    die "unsupported OS '$fake_os': run browser-use inside WSL on Windows" 1
    ;;
esac

# --- uv --------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  for candidate in "$HOME/.local/bin/uv" "/root/.local/bin/uv"; do
    if [ -x "$candidate" ]; then PATH="$candidate:$PATH"; export PATH; break; fi
  done
fi
if ! command -v uv >/dev/null 2>&1; then
  if [ "$BOOTSTRAP_UV" -eq 1 ]; then
    log "uv not found; bootstrapping via astral.sh"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    PATH="$HOME/.local/bin:$PATH"; export PATH
  else
    printf '%s\n' "ERROR: uv not found on PATH." >&2
    printf '%s\n' "Fix: install uv (https://docs.astral.sh/uv/getting-started/installation/)" >&2
    printf '%s\n' "or re-run this script with --bootstrap-uv to install it for you." >&2
    exit 2
  fi
fi

# --- Python 3.12 + tool install ---------------------------------------------
log "ensuring Python $PY (uv-managed)"
uv python install "$PY"

log "installing/upgrading $PACKAGE (uv tool, Python $PY)"
uv tool install --python "$PY" --upgrade --force "$PACKAGE"

# Resolve the bin dir uv wrote to (sandboxable via UV_TOOL_BIN_DIR).
BIN_DIR="${UV_TOOL_BIN_DIR:-$HOME/.local/bin}"
BU_BIN="$BIN_DIR/browser-use"
[ -x "$BU_BIN" ] || die "uv reported success but $BU_BIN is not executable" 1
PATH="$BIN_DIR:$PATH"; export PATH

log "installed $("$BU_BIN" --version)"

# --- Vendor skill registration ----------------------------------------------
if [ "$NO_SKILL" -eq 0 ]; then
  log "registering vendor skill (browser-use skill install)"
  bash "$(dirname "$0")/register-browser-use-skills.sh" "$BU_BIN" ||
    die "vendor skill registration failed" 1
else
  log "skipping vendor skill registration (--no-skill)"
fi

# --- Doctor + platform hints --------------------------------------------------
doctor_status=0
"$BU_BIN" --doctor || doctor_status=$?
if [ "$doctor_status" -ne 0 ]; then
  if [ "$STRICT_DOCTOR" -eq 1 ]; then
    die "doctor unhealthy (exit $doctor_status); see references/platforms.md" 1
  fi
  warn "doctor reported problems (exit $doctor_status) — usually the browser " \
       "connection gate; see references/platforms.md. Install itself is fine."
fi

case "$fake_os" in
  Darwin)
    printf '%s\n' "macOS notes: first connection needs the one-time Chrome toggle" \
      "(chrome://inspect/#remote-debugging), then \`$BU_BIN mac-approve\` for the" \
      "per-connection Allow sheet (needs Accessibility for the launching app)." ;;
  Linux)
    if command -v snap >/dev/null 2>&1 && snap list chromium >/dev/null 2>&1; then
      warn "Snap Chromium detected: CDP is blocked by default. Run: $BU_BIN doctor --fix-snap"
    fi
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
      warn "No display server detected (headless): set BU_CDP_WS to a remote" \
           "browser or run \`$BU_BIN auth login\` for cloud browsers."
    fi
    ;;
esac

log "done: $PACKAGE $("$BU_BIN" --version)"
[ "$doctor_status" -eq 0 ] || exit 0
exit 0
