#!/usr/bin/env bash
# The identity gate must block a commit authored under another vault's domain,
# allow its own, report an unset policy without blocking, and honour the
# bypass. Identity is set with GIT_AUTHOR_EMAIL, which is how git resolves it;
# `-c user.email` loses to an exported env var.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/../../bin/git-hooks" && pwd)/pre-commit-identity"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/identity-hook.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q . && mkdir -p hooks && cp "$HOOK" hooks/pre-commit && chmod +x hooks/pre-commit
git config core.hooksPath hooks

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
DOM=users.noreply.github.com
RIGHT=cheshirecode@users.noreply.github.com
WRONG=someone@example-work.invalid

# The hook reads only GIT_AUTHOR_IDENT, but git still needs a committer
# identity to land any case at all. Carry it in env so the fixture does not
# depend on a global user.name (CI sets one; a dev machine may not).
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=fixture@example.invalid

stage() { echo "$RANDOM" > "$1"; git add "$1"; }
landed() { git log --oneline -1 2>/dev/null | grep -q "$1"; }

# 1. Policy unset: reported, and the commit proceeds (the gate must not block a
# vault that has not opted in).
stage a.md
out="$(GIT_AUTHOR_EMAIL=$RIGHT GIT_AUTHOR_NAME=t git commit -m unset-case 2>&1)"
landed unset-case || note "blocked a commit while the policy was unset"
printf '%s' "$out" | grep -q "WORKLOG_IDENTITY_DOMAIN unset" || note "unset policy was not reported"

# 2. Matching domain: allowed.
stage b.md
GIT_AUTHOR_EMAIL=$RIGHT GIT_AUTHOR_NAME=t WORKLOG_IDENTITY_DOMAIN=$DOM \
  git commit -q -m match-case 2>/dev/null
landed match-case || note "blocked the vault's own identity"

# 3. Wrong domain: blocked.
stage c.md
GIT_AUTHOR_EMAIL=$WRONG GIT_AUTHOR_NAME=t WORKLOG_IDENTITY_DOMAIN=$DOM \
  git commit -q -m wrong-case 2>/dev/null
landed wrong-case && note "committed under the wrong vault's identity"

# 4. Documented bypass: honoured, or people delete the hook.
GIT_AUTHOR_EMAIL=$WRONG GIT_AUTHOR_NAME=t WORKLOG_IDENTITY_DOMAIN=$DOM \
  WORKLOG_NO_IDENTITY_HOOK=1 git commit -q -m bypass-case 2>/dev/null
landed bypass-case || note "WORKLOG_NO_IDENTITY_HOOK=1 did not bypass"

[ "$fails" -eq 0 ] || exit 1
echo "ok: identity gate blocks the wrong vault, allows the right one, reports unset, honours bypass"
