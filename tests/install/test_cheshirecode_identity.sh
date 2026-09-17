#!/usr/bin/env bash
# The cheshireCode identity must apply from any checkout and never to a repo
# owned by someone else.
#
# Asserts four things separately: the identity file is linked into $DEST,
# .gitconfig names no checkout path, the include resolves for every owner URL
# form (git's glob is case-sensitive and treats the scp colon and https slash
# differently), and it leaks onto none of the foreign forms.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-identity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
mkdir -p "$DEST"

out="$(cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" \
  HOOK_BIN_DIR="$TMP/hookbin" bash install.sh 2>&1)"

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
  'git@gh-cheshirecode:cheshirecode/dotfiles.git' \
  'git@github.com:cheshirecode/dotfiles.git' \
  'https://github.com/cheshirecode/dotfiles.git'
do
  got="$(identity_for "$url")"
  [ "$got" = "$want" ] || note "cheshireCode identity did not apply for $url (got '${got:-none}')"
done

# 4. It must NOT leak onto a repository owned by anyone else. An SSH host alias
# can itself carry the owner name (the git@host-<owner>: form), so a looser glob
# would match a third party's repo cloned through that alias and sign their
# commit with this identity. The foreign owners below are placeholders on
# purpose: no real account name other than cheshirecode belongs in this repo.
for url in \
  'git@gh-cheshirecode:other-owner/dotfiles.git' \
  'git@github.com:other-owner/dotfiles.git' \
  'https://github.com/another-org/project.git'
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
