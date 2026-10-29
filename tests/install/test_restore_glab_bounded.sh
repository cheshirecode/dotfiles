#!/usr/bin/env bash
# restore-home-links.sh runs on every SessionStart, so no call in it may block
# without bound. glab checks for a new release over the network when its config
# is fresh, and a `glab config get` blocked for 9 minutes (2026-10-07). A stub
# glab that never returns must be cut off, and the run must still exit 0.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/restore-glab.XXXXXX")"
trap 'pkill -f "$TMP/bin/glab" 2>/dev/null; rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$TMP/bin" "$TMP/home"
printf '#!/bin/sh\necho "$*" >> "%s/glab.calls"\nexec sleep 300\n' "$TMP" > "$TMP/bin/glab"
chmod +x "$TMP/bin/glab"

# The outer timeout only turns a regression into a red instead of a hung suite;
# the assertions are on what ran, not on how long it took.
timeout 60 env -i PATH="$TMP/bin:$PATH" HOME="$TMP/home" RESTORE_GLAB_TIMEOUT=1 \
  WORKLOG_HOOKS_REPO='' ENV_SECRETS=/nonexistent AWS_CANON=/nonexistent AWS_SSO_CACHE='' \
  VAULT_STAMP="$TMP/stamp" bash "$SCRIPT" > "$TMP/out" 2>&1
rc=$?
[ "$rc" = 124 ] && note "the run was still blocked on glab after 60s"
[ "$rc" = 0 ] || [ "$rc" = 124 ] || note "the run exited $rc, want 0"
grep -q '^config get git_protocol' "$TMP/glab.calls" 2>/dev/null || note "glab was never called, so nothing was tested"
[ "$(grep -c . "$TMP/glab.calls" 2>/dev/null)" -le 2 ] || note "glab was called more than get + one set"
grep -q 'glab -> https' "$TMP/out" && note "claimed glab was switched to https when the set timed out"

[ "$fails" -eq 0 ] || { cat "$TMP/out"; exit 1; }
echo "ok: a glab that never returns is cut off and the session-start hook still exits 0"
