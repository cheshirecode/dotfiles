#!/usr/bin/env bash
# The leak guard and its pre-commit hook must block work identifiers and
# hardcoded home paths, and must NOT block placeholders.
#
# Both halves matter. A guard that blocks everything gets bypassed or deleted;
# the placeholder case is why the path pattern classifies a username rather than
# banning every /home/<x>/ (a WSL tutorial's /home/user/project is correct).
#
# Runs in a disposable repo, so no real commit is ever at risk.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leakguard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

git init -q . && git config user.email t@t.invalid && git config user.name t
mkdir -p bin/git-hooks
cp "$REPO/bin/leak-guard.sh" bin/
cp "$REPO/bin/git-hooks/pre-commit" bin/git-hooks/
cp "$REPO/bin/install-hooks.sh" bin/
git add -A
git -c core.hooksPath=/dev/null commit -q -m seed
bash bin/install-hooks.sh --write >/dev/null

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
committed() { git log --oneline -1 2>/dev/null | grep -q "$1"; }

# 1. A clean commit must not be blocked.
echo "nothing notable" > ok.md; git add ok.md
git commit -q -m "clean-case" 2>/dev/null
committed clean-case || note "blocked a clean commit"

# 2. A work identifier must block.
echo "see ideogram-ai/ui" > leak.md; git add leak.md   # pragma: allowlist owner
git commit -q -m "leak-case" 2>/dev/null
committed leak-case && note "committed a work identifier"

# 3. A hardcoded home path must block.
git reset -q
echo "PATH=/home/fred/bin" > path.md; git add path.md   # pragma: allowlist owner
git commit -q -m "path-case" 2>/dev/null
committed path-case && note "committed a hardcoded home path"

# 4. A placeholder home path must NOT block.
git reset -q
echo "PATH=/home/user/bin" > ph.md; git add ph.md
git commit -q -m "placeholder-case" 2>/dev/null
committed placeholder-case || note "blocked a placeholder home path"

# 5. The documented bypass must work, or people will delete the hook.
git reset -q
echo "see ideogram-ai/ui" > by.md; git add by.md   # pragma: allowlist owner
DOTFILES_NO_HOOK=1 git commit -q -m "bypass-case" 2>/dev/null
committed bypass-case || note "DOTFILES_NO_HOOK=1 did not bypass"

# 6. Tree mode must find what staged mode would have blocked.
git reset -q
printf 'PATH=/home/fred/bin\n' > tracked.md   # pragma: allowlist owner
git add tracked.md && DOTFILES_NO_HOOK=1 git commit -q -m "tracked" 2>/dev/null
bin/leak-guard.sh --tree >/dev/null 2>&1 && note "tree mode missed a committed leak"

[ "$fails" -eq 0 ] || exit 1
echo "ok: leak guard blocks identifiers and real home paths, allows placeholders, honours the bypass"
