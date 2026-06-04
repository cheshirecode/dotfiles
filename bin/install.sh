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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-deps)  SKIP_DEPS=1 ;;
    --no-worklog) NO_WORKLOG=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "install: unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done

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
cd "$REPO_ROOT"

echo "=== install: detected $OS ==="

if [[ $SKIP_DEPS -eq 0 ]]; then
  echo
  echo "=== 1/4 runtime deps ==="
  bin/install-runtime-deps.sh
else
  echo "=== 1/4 runtime deps SKIPPED (--skip-deps) ==="
fi

echo
echo "=== 2/4 agent skills ==="
bin/install-skills.sh

if [[ $NO_WORKLOG -eq 0 ]]; then
  echo
  echo "=== 3/4 worklog ==="
  bin/install-worklog.sh
else
  echo "=== 3/4 worklog SKIPPED (--no-worklog) ==="
fi

echo
echo "=== 4/4 doctor ==="
bin/doctor.sh

echo
echo "install: done"
