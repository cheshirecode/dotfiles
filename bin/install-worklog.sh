#!/usr/bin/env bash
# Clone the _worklog repo into $PROJECTS_DIR, wire its hooks, verify.
#
# Default upstream: cheshirecode/_worklog. Override via WORKLOG_REPO env.
# Default location: $PROJECTS_DIR/_worklog (PROJECTS_DIR defaults to ~/Documents/projects).
#
# Idempotent. Re-running pulls + re-wires hooks.

set -euo pipefail

WORKLOG_REPO="${WORKLOG_REPO:-cheshirecode/_worklog}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"
TARGET="$PROJECTS_DIR/_worklog"

mkdir -p "$PROJECTS_DIR"

if [[ ! -d "$TARGET/.git" ]]; then
  echo "install-worklog: cloning $WORKLOG_REPO → $TARGET"
  if command -v gh >/dev/null; then
    gh repo clone "$WORKLOG_REPO" "$TARGET" --
  else
    git clone "https://github.com/$WORKLOG_REPO.git" "$TARGET"
  fi
else
  echo "install-worklog: $TARGET present — pulling latest"
  git -C "$TARGET" pull --ff-only --autostash
fi

# Wire hooks (PreCompact + SessionEnd autosave/compact-kernels).
if [[ -x "$TARGET/bin/install-hooks.sh" ]]; then
  echo "install-worklog: wiring hooks"
  "$TARGET/bin/install-hooks.sh" --write
else
  echo "install-worklog: WARN — $TARGET/bin/install-hooks.sh not found, skipping hook wire-up" >&2
fi

# Smoke: status should not error.
if [[ -x "$TARGET/bin/status.sh" ]]; then
  echo "install-worklog: smoke-test bin/status.sh"
  "$TARGET/bin/status.sh" --quiet 2>&1 | head -5 || {
    echo "install-worklog: WARN — bin/status.sh exited non-zero (may need LDAP setup)" >&2
  }
fi

echo "install-worklog: done — worklog repo at $TARGET"
echo "install-worklog: next: /worklog init  (inside Claude Code)"
