#!/usr/bin/env bash
# The per-vault identity gate must block a commit authored under the other
# vault's domain, allow the right one, report an unset policy rather than
# silently passing, and honour its documented bypass.
#
# Why it exists: the two vaults cross-contaminated — 795 personal-identity and
# 210 oss@local commits in the work vault, 37 work-identity commits in the
# personal one (measured 2026-09-16). Both private, so hygiene not exposure,
# but each was preventable at commit time and unfixable afterwards without
# rewriting thousands of commits across live worktrees.
#
# Identity is set with GIT_AUTHOR_EMAIL, not `-c user.email`. The env wins over
# config, and a first version of this test used -c while the session's own
# GIT_AUTHOR_EMAIL was exported — so the "wrong identity" case committed under
# the RIGHT identity and the hook looked broken when the fixture was.
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
