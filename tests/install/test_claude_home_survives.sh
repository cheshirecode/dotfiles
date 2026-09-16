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

# The .config children loop is a SECOND call site for the same guard, and it
# was unwired: it called backup() and ln -sfn directly, so a real
# ~/.config/opencode was moved aside and the repo directory linked over it.
# Reported 2026-09-16 after 11 local items vanished from the live path.
mkdir -p "$DEST/.config/opencode/plugins"
printf '%s\n' '{"local":"tui"}' > "$DEST/.config/opencode/tui.jsonc"
printf '%s\n' 'local plugin' > "$DEST/.config/opencode/plugins/mine.js"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  bash install.sh 2>&1)"
status=$?

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

if [ -L "$DEST/.claude" ]; then
  note "DEST/.claude was replaced by a symlink to $(readlink "$DEST/.claude")"
fi
if [ ! -f "$DEST/.claude/settings.json" ]; then
  note "DEST/.claude/settings.json is gone"
elif ! grep -q 'user-settings' "$DEST/.claude/settings.json"; then
  note "DEST/.claude/settings.json no longer holds the user's content"
fi
if [ ! -f "$DEST/.claude/projects/session.jsonl" ]; then
  note "DEST/.claude/projects/session.jsonl is gone"
fi
if [ -e "$DEST/.claude.bak" ] || [ -L "$DEST/.claude.bak" ]; then
  note "installer moved the real DEST/.claude aside to .claude.bak"
fi
if [ -L "$DEST/.config/opencode" ]; then
  note "DEST/.config/opencode was replaced by a symlink to $(readlink "$DEST/.config/opencode")"
fi
if [ ! -f "$DEST/.config/opencode/tui.jsonc" ]; then
  note "DEST/.config/opencode/tui.jsonc is gone"
fi
if [ ! -f "$DEST/.config/opencode/plugins/mine.js" ]; then
  note "DEST/.config/opencode/plugins/mine.js is gone"
fi
if [ -e "$DEST/.config/opencode.bak" ] || [ -L "$DEST/.config/opencode.bak" ]; then
  note "installer moved the real DEST/.config/opencode aside to opencode.bak"
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
