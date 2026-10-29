#!/usr/bin/env bash
# Run from Coder's own clone, install.sh must replace that clone with a link to
# the primary checkout when the clone is clean and the primary holds its
# commit, and must leave it alone otherwise. The real-world start is covered:
# ~/.bashrc links into the clone and carries the template's append.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-dedupe.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
G=(-c user.name=t -c user.email=t@example.invalid -c core.hooksPath=/dev/null)  # a global commit hook must not judge fixture commits

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# The primary is built from this working tree, not from HEAD, so the change
# under test is what runs, and the test also works from a copy with no .git.
mk_primary() {  # <dir>
  mkdir -p "$1" && (cd "$REPO" && tar --exclude=./.git -cf - .) | (cd "$1" && tar -xf -) &&
    git -C "$1" init -q && git -C "$1" add -A && git "${G[@]}" -C "$1" commit -qm snapshot
}

run_from_clone() {  # <home> -> installer output
  env HOME="$1" CODER_SYMLINK_DIR="$1" HOOK_BIN_DIR="$1/hookbin" \
    DOTFILES_PRIMARY="$PRIMARY" bash "$1/.config/coder-clone/dotfiles/install.sh" 2>&1
}

PRIMARY="$TMP/primary"
mk_primary "$PRIMARY" || { echo "FAIL: could not build the primary fixture"; exit 1; }
PRIMARY="$(cd "$PRIMARY" && pwd -P)"

# --- Case 1: clean clone, ~/.bashrc linked into it with a template append.
H1="$TMP/h1"; C1="$H1/.config/coder-clone/dotfiles"; mkdir -p "$H1/.config/coder-clone"
git clone -q "$PRIMARY" "$C1"
printf 'echo template-line\n' >> "$C1/.bashrc"
ln -s "$C1/.bashrc" "$H1/.bashrc"
out1="$(run_from_clone "$H1")"

if [ ! -L "$C1" ]; then
  note "case 1: a clean clone was kept instead of replaced by a link"
else
  [ "$(readlink "$C1")" = "$PRIMARY" ] || note "case 1: the clone link points at $(readlink "$C1"), not the primary"
fi
ls -d "$C1".bak-* >/dev/null 2>&1 || note "case 1: the old clone was not kept aside"
[ "$(sed -n 2p "$H1/.bashrc" 2>/dev/null)" = ". \"$PRIMARY/.bashrc\"" ] ||
  note "case 1: the ~/.bashrc stub does not source the primary"
grep -qx 'echo template-line' "$H1/.bashrc" 2>/dev/null || note "case 1: the template's appended line was lost"
[ -z "$(git -C "$PRIMARY" status --porcelain)" ] || note "case 1: the primary checkout was left dirty"
[ "$(readlink -f "$H1/.bash_profile" 2>/dev/null)" = "$PRIMARY/.bash_profile" ] ||
  note "case 1: ~/.bash_profile does not resolve into the primary"
printf '%s\n' "$out1" | grep -q 'Dotfiles installation complete.' || note "case 1: installer did not reach its last line"

# --- Case 2: a dirty clone is kept.
H2="$TMP/h2"; C2="$H2/.config/coder-clone/dotfiles"; mkdir -p "$H2/.config/coder-clone"
git clone -q "$PRIMARY" "$C2"; echo wip > "$C2/untracked-work.txt"
out2="$(run_from_clone "$H2")"
{ [ -d "$C2" ] && [ ! -L "$C2" ]; } || note "case 2: a clone with uncommitted work was replaced"
printf '%s\n' "$out2" | grep -q 'uncommitted changes' || note "case 2: the refusal did not say why"

# --- Case 3: a clone ahead of the primary is kept.
H3="$TMP/h3"; C3="$H3/.config/coder-clone/dotfiles"; mkdir -p "$H3/.config/coder-clone"
git clone -q "$PRIMARY" "$C3"; git "${G[@]}" -C "$C3" commit -q --allow-empty -m ahead
out3="$(run_from_clone "$H3")"
{ [ -d "$C3" ] && [ ! -L "$C3" ]; } || note "case 3: a clone with a commit the primary lacks was replaced"
printf '%s\n' "$out3" | grep -q 'lacks the clone' || note "case 3: the refusal did not say why"

if [ "$fails" -ne 0 ]; then
  for o in out1 out2 out3; do echo "--- $o ---"; printf '%s\n' "${!o}" | tail -8; done
  exit 1
fi
echo "ok: a clean Coder clone becomes a link to the primary; dirty or ahead clones are kept"
