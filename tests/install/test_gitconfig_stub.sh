#!/usr/bin/env bash
# install.sh must make ~/.gitconfig a machine-local stub that includes the
# tracked .gitconfig, so `git config --global` (the Coder template sets an
# identity at start) never writes into a checkout, and a globally written
# identity sits ABOVE the include where it cannot override the tracked rules.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-gitconfig.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
MARK='# dotfiles install.sh: includes the tracked .gitconfig. Lines below are machine-local.'

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

run_install() {  # <home>
  (cd "$REPO" && env -i HOME="$1" PATH=/usr/bin:/bin:/usr/local/bin CODER_SYMLINK_DIR="$1" \
    HOOK_BIN_DIR="$1/hookbin" DOTFILES_PRIMARY="$TMP/no-primary" bash install.sh 2>&1)
}
g() { env -i HOME="$1" PATH=/usr/bin:/bin:/usr/local/bin git "${@:2}"; }  # git as that home sees it
personal() {  # <home>: the per-machine fallback identity install.sh's include reaches
  printf '[user]\n\tname = Personal\n\temail = personal@example.invalid\n' > "$1/.gitconfig.local"
}
repo_cfg_before="$(cksum < "$REPO/.gitconfig")"

# --- Case 1: a link into a checkout whose .gitconfig carries a template [user].
H1="$TMP/h1"; mkdir -p "$H1" "$TMP/old"; personal "$H1"
git -C "$TMP/old" init -q
printf '[alias]\n\tst = status\n' > "$TMP/old/.gitconfig"
git -C "$TMP/old" add .gitconfig
git -C "$TMP/old" -c user.name=t -c user.email=t@example.invalid -c core.hooksPath=/dev/null commit -qm init
printf '[user]\n\tname = Template\n\temail = template@example.invalid\n' >> "$TMP/old/.gitconfig"
ln -s "$TMP/old/.gitconfig" "$H1/.gitconfig"
out1="$(run_install "$H1")"

if [ -L "$H1/.gitconfig" ] || [ ! -f "$H1/.gitconfig" ]; then
  note "case 1: ~/.gitconfig is still a symlink, not a stub"
else
  [ "$(head -n 1 "$H1/.gitconfig")" = "$MARK" ] || note "case 1: stub does not start with the marker"
  [ "$(git config --file "$H1/.gitconfig" --get include.path)" = "$REPO/.gitconfig" ] ||
    note "case 1: the stub does not include $REPO/.gitconfig"
  [ "$(git config --file "$H1/.gitconfig" --get user.email)" = template@example.invalid ] ||
    note "case 1: the appended identity was not carried into the stub"
  u="$(grep -n '^\[user\]' "$H1/.gitconfig" | head -n 1 | cut -d: -f1)"
  i="$(grep -n '^\[include\]' "$H1/.gitconfig" | head -n 1 | cut -d: -f1)"
  { [ -n "$u" ] && [ -n "$i" ] && [ "$u" -lt "$i" ]; } || note "case 1: [user] does not come before the include"
  [ "$(grep -c '^\[user\]' "$H1/.gitconfig")" = 1 ] || note "case 1: the carried identity added a second [user] section"
fi
[ -z "$(git -C "$TMP/old" status --porcelain)" ] || note "case 1: the linked checkout's .gitconfig was not put back to HEAD"

# --- Case 2: identity. Outside any repo the personal fallback wins over the
# template's, and a later template write changes the stub, not the checkout.
(cd "$TMP" && [ "$(g "$H1" config user.email)" = personal@example.invalid ]) ||
  note "case 2: the template identity overrides ~/.gitconfig.local"
g "$H1" config --global user.email template2@example.invalid
grep -q 'template2@example.invalid' "$H1/.gitconfig" || note "case 2: git config --global did not write the stub"
(cd "$TMP" && [ "$(g "$H1" config user.email)" = personal@example.invalid ]) ||
  note "case 2: a later template write overrides ~/.gitconfig.local"
[ "$(grep -c '^\[user\]' "$H1/.gitconfig")" = 1 ] || note "case 2: git config --global added a [user] after the include"

# --- Case 3: a rerun changes nothing.
before="$(cksum < "$H1/.gitconfig")"
run_install "$H1" >/dev/null
[ "$(cksum < "$H1/.gitconfig")" = "$before" ] || note "case 3: a rerun changed the stub"

# --- Case 4: a stub from a checkout that moved is repointed; machine-local keys kept.
H4="$TMP/h4"; mkdir -p "$H4"
printf '%s\n[user]\n\temail = local@example.invalid\n[include]\n\tpath = /gone/dotfiles/.gitconfig\n' "$MARK" > "$H4/.gitconfig"
run_install "$H4" >/dev/null
[ "$(git config --file "$H4/.gitconfig" --get include.path)" = "$REPO/.gitconfig" ] || note "case 4: a stale include was not repointed"
[ "$(git config --file "$H4/.gitconfig" --get user.email)" = local@example.invalid ] || note "case 4: repointing dropped a machine-local key"

[ "$(cksum < "$REPO/.gitconfig")" = "$repo_cfg_before" ] || note "the checkout's own .gitconfig changed during the run"
printf '%s\n' "$out1" | grep -q 'Dotfiles installation complete.' || note "installer did not reach its last line"

if [ "$fails" -ne 0 ]; then
  echo "--- installer output (case 1) ---"; printf '%s\n' "$out1" | tail -12
  echo "--- stub (case 1) ---"; sed 's/email = .*/email = <e>/' "$H1/.gitconfig" 2>/dev/null
  exit 1
fi
echo "ok: ~/.gitconfig is a stub; a global identity write stays machine-local and below the tracked rules"
