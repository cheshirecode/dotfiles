#!/usr/bin/env bash
# The ~/.gitconfig.local seed carries the PERSONAL fallback identity, derived
# from the tracked .gitconfig.cheshireCode so the identity has one copy in
# the repo. An untouched seed from the empty-template era upgrades in place;
# a .local the machine has edited is never ours to replace.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/install-gitlocal.XXXXXX")"
trap 'rm -rf "$BASE"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

run_install() { # run_install <home> -> installer output
  local home="$1"
  (cd "$REPO" && env HOME="$home" CODER_SYMLINK_DIR="$home" \
    HOOK_BIN_DIR="$BASE/hookbin" bash install.sh 2>&1)
}

# Expectations come from the tracked identity file, not from literals here:
# the seed's job is to carry THAT file's values, so a changed identity must
# change the expectation too, not break a second copy of it.
want_name="$(git config -f "$REPO/.gitconfig.cheshireCode" user.name)"
want_email="$(git config -f "$REPO/.gitconfig.cheshireCode" user.email)"
[[ -n "$want_name" && -n "$want_email" ]] \
  || { echo "FAIL: no identity in the repo's .gitconfig.cheshireCode to seed from"; exit 1; }

old_seed='# Per-machine git identity. Add a [user] block here; do not commit this file.
[user]
	# name = Your Name
	# email = you@example.com'

# 1. Fresh install seeds the personal fallback identity, not an empty template.
H1="$BASE/home1"; mkdir -p "$H1"
out="$(run_install "$H1")"
grep -q "name = $want_name" "$H1/.gitconfig.local" \
  || note "fresh .gitconfig.local carries no personal name"
grep -q "email = $want_email" "$H1/.gitconfig.local" \
  || note "fresh .gitconfig.local carries no personal email"
grep -q 'Dotfiles installation complete.' <<< "$out" \
  || note "installer (fresh) did not reach its last line"

# 2. Re-run is idempotent: the seed is written once, not rewritten.
cp "$H1/.gitconfig.local" "$BASE/first.local"
out="$(run_install "$H1")"
cmp -s "$BASE/first.local" "$H1/.gitconfig.local" \
  || note "re-run rewrote .gitconfig.local"
grep -q 'Dotfiles installation complete.' <<< "$out" \
  || note "installer (re-run) did not reach its last line"

# 3. An untouched seed from the empty-template era upgrades in place. This is
# the machine shape that shipped before the posture existed: its fallback was
# empty, so cheshirecode remotes fell through to git's machine default.
H2="$BASE/home2"; mkdir -p "$H2"
printf '%s\n' "$old_seed" > "$H2/.gitconfig.local"
out="$(run_install "$H2")"
grep -q "name = $want_name" "$H2/.gitconfig.local" \
  || note "empty-template .gitconfig.local was not upgraded to the personal fallback"
grep -q "email = $want_email" "$H2/.gitconfig.local" \
  || note "empty-template .gitconfig.local was not upgraded to the personal email"
grep -q 'Dotfiles installation complete.' <<< "$out" \
  || note "installer (upgrade) did not reach its last line"

# 4. A .local the machine has edited is not ours to replace. Its identity
# decisions are the machine's; the upgrade must exact-match the old template
# and nothing else.
H3="$BASE/home3"; mkdir -p "$H3"
printf '[user]\n\tname = Custom\n\temail = custom@example.invalid\n' > "$H3/.gitconfig.local"
out="$(run_install "$H3")"
printf '[user]\n\tname = Custom\n\temail = custom@example.invalid\n' > "$BASE/expected-custom"
cmp -s "$BASE/expected-custom" "$H3/.gitconfig.local" \
  || note "custom .gitconfig.local was overwritten"
grep -q 'Dotfiles installation complete.' <<< "$out" \
  || note "installer (custom) did not reach its last line"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: .gitconfig.local seeds personal, upgrades the untouched empty template, leaves edits alone"