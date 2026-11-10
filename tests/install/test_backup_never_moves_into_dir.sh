#!/usr/bin/env bash
# backup() must rename a target, never move it INTO a directory. When
# "$target.bak" already exists as a symlink to a directory, a bare
# `mv "$target" "$target.bak"` follows the link and drops the target inside
# that directory. Measured 2026-10-28: 21 stale skill links landed as
# skills/<name>/<name> inside the checkout, because each root already held
# <name>.bak -> the checkout's skills/<name>.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-backup-dir.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
TRAP_DIR="$TMP/some-directory"
mkdir -p "$DEST" "$TRAP_DIR"

# A real file the installer must back up, and an earlier backup that is a
# symlink to a directory.
printf 'my own zshrc\n' > "$DEST/.zshrc"
ln -s "$TRAP_DIR" "$DEST/.zshrc.bak"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  bash install.sh 2>&1)"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

if [ -n "$(ls -A "$TRAP_DIR")" ]; then
  note "backup moved the target into the directory .zshrc.bak points at: $(ls -A "$TRAP_DIR" | tr '\n' ' ')"
fi
if ! grep -rqs 'my own zshrc' "$DEST"/.zshrc.bak?*; then
  note "the original .zshrc content was not kept in a fresh .zshrc.bak* file"
fi
if [ "$(readlink "$DEST/.zshrc")" != "$REPO/.zshrc" ]; then
  note ".zshrc is not linked to the repo copy (got: $(readlink "$DEST/.zshrc"))"
fi
if ! printf '%s\n' "$out" | grep -q 'Dotfiles installation complete.'; then
  note "installer did not reach its last line"
fi

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -15
  exit 1
fi
echo "ok: backup renames beside an existing .bak link instead of moving into it"
