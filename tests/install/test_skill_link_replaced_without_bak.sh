#!/usr/bin/env bash
# A skill root entry that is already a symlink holds no data, so install.sh
# must replace it in place, not back it up. Each backup left <name>.bak
# beside it, which every skill host then loaded as a second copy of the skill
# (council and council.bak, 21 times over in three roots).

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-skill-relink.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
mkdir -p "$DEST"
# The same checkout reached through another path, as the Coder clone link is.
ln -s "$REPO" "$TMP/alias"

roots=(.agents/skills .claude/skills .cursor/skills)
for r in "${roots[@]}"; do
  mkdir -p "$DEST/$r"
  ln -s "$TMP/alias/skills/council" "$DEST/$r/council"   # same dir, other path
  ln -s "$TMP/gone/skills/pr-review" "$DEST/$r/pr-review" # dangling
done

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  bash install.sh 2>&1)"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

checked=0
for r in "${roots[@]}"; do
  for s in council pr-review; do
    checked=$((checked + 1))
    if [ -e "$DEST/$r/$s.bak" ] || [ -L "$DEST/$r/$s.bak" ]; then
      note "$r/$s.bak was created for a symlink"
    fi
    if [ "$(readlink "$DEST/$r/$s")" != "$REPO/skills/$s" ]; then
      note "$r/$s does not point at $REPO/skills/$s (got: $(readlink "$DEST/$r/$s"))"
    fi
  done
done
want=$(( ${#roots[@]} * 2 ))
[ "$checked" -eq "$want" ] || note "expected $want root entries checked, ran $checked"
if ! printf '%s\n' "$out" | grep -q 'Dotfiles installation complete.'; then
  note "installer did not reach its last line"
fi

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -15
  exit 1
fi
echo "ok: skill symlinks replaced in place, no .bak duplicates"
