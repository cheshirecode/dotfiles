#!/usr/bin/env bash
# One-shot installer entry point. Detects OS, then orchestrates:
#   1. install-runtime-deps.sh  — python/gh/git/rg/jq/direnv
#   2. install-skills.sh        — symlink/copy agent skills from manifest
#   3. install-worklog.sh       — clone _worklog repo + wire hooks
#   4. doctor.sh                — verify
#
# Refuses Windows-native. WSL2 is the supported Windows path.
#
# Usage:
#   bin/install.sh             # full install
#   bin/install.sh --skip-deps # skip package-manager step (CI environments
#                              # that already have deps baked into the image)
#   bin/install.sh --no-worklog # don't clone _worklog (skills-only install)

set -euo pipefail

SKIP_DEPS=0
NO_WORKLOG=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-deps)  SKIP_DEPS=1 ;;
    --no-worklog) NO_WORKLOG=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)
      # HELP-START
      cat <<'EOF'
install.sh — one-shot installer entry point. Detects OS and orchestrates:
  1. install-runtime-deps.sh
  2. install-skills.sh
  3. install-worklog.sh
  4. doctor.sh

Refuses Windows-native. WSL2 is the supported Windows path.

Usage:
  bin/install.sh             # full install
  bin/install.sh --skip-deps # skip package-manager step (CI images that
                             # bake deps in)
  bin/install.sh --no-worklog # don't clone _worklog (skills-only install)
  bin/install.sh --dry-run    # print intended actions; do nothing
EOF
      # HELP-END
      exit 0
      ;;
    *) echo "install: unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done

# Council guardrail: ERR trap → tell the user where we stopped so they
# can run bin/doctor.sh and re-run install.sh idempotently. Don't leave
# them guessing about a half-applied install.
on_err() {
  echo >&2
  echo "install: FAILED partway through. The install is idempotent — fix the" >&2
  echo "  underlying issue and re-run bin/install.sh. To diagnose: bin/doctor.sh" >&2
}
trap on_err ERR

# OS gate.
OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;  # supported
  MINGW*|MSYS*|CYGWIN*)
    cat >&2 <<EOF
install: native Windows is not supported.

Use WSL2:
  1. Install WSL2: https://learn.microsoft.com/windows/wsl/install
  2. Launch Ubuntu (or your distro of choice).
  3. git clone this repo INSIDE WSL2 (not on /mnt/c/) and re-run bin/install.sh.
EOF
    exit 1
    ;;
  *)
    echo "install: unsupported OS '$OS'" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run sub-scripts in a subshell with explicit cwd; never globally chdir.
# Council guardrail: any future sub-script that reads $PWD won't see a
# surprise from install.sh's perspective.
run_step() {
  ( cd "$REPO_ROOT" && "$@" )
}

echo "=== install: detected $OS ==="
[[ $DRY_RUN -eq 1 ]] && echo "    (dry-run mode — printing actions, not executing)"

if [[ $SKIP_DEPS -eq 0 ]]; then
  echo
  echo "=== 1/4 runtime deps ==="
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] would run: bin/install-runtime-deps.sh"
  else
    run_step bin/install-runtime-deps.sh
  fi
else
  echo "=== 1/4 runtime deps SKIPPED (--skip-deps) ==="
fi

echo
echo "=== 2/4 agent skills ==="
if [[ $DRY_RUN -eq 1 ]]; then
  run_step bin/install-skills.sh --dry-run
else
  run_step bin/install-skills.sh
fi

if [[ $NO_WORKLOG -eq 0 ]]; then
  echo
  echo "=== 3/4 worklog ==="
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] would run: bin/install-worklog.sh"
  else
    run_step bin/install-worklog.sh
  fi
else
  echo "=== 3/4 worklog SKIPPED (--no-worklog) ==="
fi

echo
echo "=== 4/4 doctor ==="
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] would run: bin/doctor.sh"
else
  run_step bin/doctor.sh
fi

echo
echo "install: done"
