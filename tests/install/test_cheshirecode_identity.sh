#!/usr/bin/env bash
# The cheshireCode identity must apply from any checkout path, and must never
# apply to a repository owned by someone else.
#
# Reported 2026-09-16: .gitconfig carried
# `path = ~/.config/coderv2/dotfiles/.gitconfig.cheshireCode`, a checkout path
# committed from a Coder workspace. On a machine whose checkout lives elsewhere
# that path does not exist, and git ignores a missing include with no error, so
# the identity silently never applied. The include pattern was broken too:
# `**/cheshireCode/**` matches neither the lowercase owner in the URL nor the
# scp-style SSH form this repo's origin uses.
#
# Two separate things are asserted, because either alone passes while the
# identity is still wrong: the file must be LINKED into $DEST by the installer,
# and the include rule must actually RESOLVE for both remote URL forms.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-identity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
mkdir -p "$DEST"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  SKIP_SUPER_RULER=1 HOOK_BIN_DIR="$TMP/hookbin" bash install.sh 2>&1)"

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# 1. The installer must put the identity file where .gitconfig looks for it.
# Removing its skip-list entry is the kind of change that silently stops
# happening, and no identity assertion below can tell that apart from a bad
# include pattern.
if [ ! -e "$DEST/.gitconfig.cheshireCode" ]; then
  note ".gitconfig.cheshireCode does not resolve in \$DEST after install"
fi

# 2. .gitconfig must not name a checkout path. Each machine has a different
# one, so a literal path here is loaded on one machine and dangling on the rest.
if grep -nE '^\s*path\s*=\s*~?/?\.?[^ ]*dotfiles/' "$REPO/.gitconfig" \
   | grep -v '^\s*#' | grep -q .; then
  note ".gitconfig names a dotfiles checkout path; it must use a \$HOME-relative name"
fi

# 3. The identity must resolve for a repo owned by cheshirecode, in BOTH remote
# URL forms. git's glob is case-sensitive and treats the scp-style colon and the
# https slash differently, so one pattern cannot cover both.
identity_for() { # identity_for <url>
  local url="$1" repo="$TMP/probe"
  rm -rf "$repo"; mkdir -p "$repo"
  git -C "$repo" init -q .
  git -C "$repo" remote add origin "$url"
  HOME="$DEST" git -C "$repo" config --get user.email 2>/dev/null
}

want="1631630+cheshirecode@users.noreply.github.com"
for url in \
  'git@<ssh-alias>:cheshirecode/dotfiles.git' \
  'git@github.com:cheshirecode/dotfiles.git' \
  'https://github.com/cheshirecode/dotfiles.git'
do
  got="$(identity_for "$url")"
  [ "$got" = "$want" ] || note "cheshireCode identity did not apply for $url (got '${got:-none}')"
done

# 4. It must NOT leak onto a repository owned by anyone else. The SSH host alias
# <ssh-alias> contains the owner name, so a looser glob would match
# an work-org repo cloned through that alias and sign a work commit with the
# personal identity.
for url in \
  'git@<ssh-alias>:<work-user>/dotfiles.git' \
  'git@github.com:<work-user>/dotfiles.git' \
  'https://github.com/<work-org>/curation.git'
do
  got="$(identity_for "$url")"
  [ -z "$got" ] || note "cheshireCode identity leaked onto $url (got '$got')"
done

if ! printf '%s\n' "$out" | grep -q 'Dotfiles installation complete.'; then
  note "installer did not reach its last line"
fi

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -15
  exit 1
fi
echo "ok: cheshireCode identity linked, resolves for both URL forms, leaks nowhere"
