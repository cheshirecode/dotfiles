#!/usr/bin/env bash
# install.sh must not replace a real ~/.claude with a symlink into the repo,
# and a dangling link under ~/.cursor must not abort the installer.
#
# Both defects are invisible on the Coder template, where ~/.claude and
# ~/.cursor are persistent-disk mountpoints: mv fails EBUSY and backup() only
# warns. They fire wherever $HOME is a plain directory, which is every laptop.
# Reported 2026-09-16 after install.sh moved a real ~/.claude (33 entries,
# settings, transcripts, memory) aside and linked the repo's gitignored
# .claude/ in its place.
#
# HOME is pinned to $DEST as well as CODER_SYMLINK_DIR: install.sh sources
# $HOME/.shell_common.vault and runs tic into $HOME/.terminfo, so an unpinned
# HOME would reach into the real one.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-claude-home.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"

mkdir -p "$DEST/.claude/projects"
printf '%s\n' '{"real":"user-settings"}' > "$DEST/.claude/settings.json"
printf '%s\n' 'session transcript' > "$DEST/.claude/projects/session.jsonl"
mkdir -p "$DEST/.cursor"
ln -s "$TMP/gone/rules" "$DEST/.cursor/rules"
ln -s "$TMP/gone/mcp.json" "$DEST/.cursor/mcp.json"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  SKIP_SUPER_RULER=1 bash install.sh 2>&1)"
status=$?

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

if [ -L "$DEST/.claude" ]; then
  note "~/.claude was replaced by a symlink to $(readlink "$DEST/.claude")"
fi
if [ ! -f "$DEST/.claude/settings.json" ]; then
  note "~/.claude/settings.json is gone"
elif ! grep -q 'user-settings' "$DEST/.claude/settings.json"; then
  note "~/.claude/settings.json no longer holds the user's content"
fi
if [ ! -f "$DEST/.claude/projects/session.jsonl" ]; then
  note "~/.claude/projects/session.jsonl is gone"
fi
if [ -e "$DEST/.claude.bak" ] || [ -L "$DEST/.claude.bak" ]; then
  note "installer moved the real ~/.claude aside to .claude.bak"
fi
if ! printf '%s\n' "$out" | grep -q 'Dotfiles installation complete.'; then
  note "installer never reached its last line (exit $status); a dangling ~/.cursor link aborted it"
fi

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -20
  exit 1
fi
echo "ok: real ~/.claude survived and the installer ran to completion"
