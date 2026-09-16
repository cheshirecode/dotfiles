#!/usr/bin/env bash
# install.sh must remove a top-level link left behind by an older checkout, and
# must leave every other dangling link alone.
#
# Reported 2026-09-16: after the checkout moved, ~/.zshenv and ~/.gitignore
# stayed dangling through a repair run, because the install loop only creates
# links for files the repo still ships and had no pass that removes the rest.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-prune.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
mkdir -p "$DEST"

# Stale: target is gone AND lay under a dotfiles checkout. Must be pruned.
ln -s "$TMP/old/projects/dotfiles/.zshenv" "$DEST/.zshenv"
ln -s "$TMP/old/projects/dotfiles/.gitignore" "$DEST/.gitignore"
# Not ours: dangling, but nothing to do with a dotfiles checkout. Must survive.
ln -s "$TMP/elsewhere/.someone-elses-rc" "$DEST/.someone-elses-rc"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  SKIP_SUPER_RULER=1 bash install.sh 2>&1)"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

for stale in .zshenv .gitignore; do
  if [ -L "$DEST/$stale" ]; then
    note "$stale is still a dangling link into a deleted dotfiles checkout"
  fi
done
if [ ! -L "$DEST/.someone-elses-rc" ]; then
  note "pruned a dangling link that does not belong to a dotfiles checkout"
fi
if ! printf '%s\n' "$out" | grep -q 'Dotfiles installation complete.'; then
  note "installer did not reach its last line"
fi

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -15
  exit 1
fi
echo "ok: stale dotfiles links pruned, unrelated dangling link left alone"
