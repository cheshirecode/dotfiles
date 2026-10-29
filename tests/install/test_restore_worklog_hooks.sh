#!/usr/bin/env bash
# restore-home-links.sh runs on every SessionStart and must leave the worklog
# clone with its git hooks: a clone made without bootstrap.sh had none, so a
# task with "status: bogus" was committed and pushed (2026-10-06). It repairs a
# missing hook, says so, stays quiet once hooked, honours the opt-out, and
# reports loudly when it cannot repair. No network; the outer hooksPath stands
# in for the platform scanner.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
SKILL_BIN="$REPO/skills/worklog/bin"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/restore-wl-hooks.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$TMP/outer"
printf '[core]\n\thooksPath = %s\n' "$TMP/outer" > "$TMP/gitconfig"

run() {  # run <repo or empty> <skill bin> -> output in $TMP/out
  env -i PATH="$PATH" HOME="$TMP/home" GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    WORKLOG_HOOKS_REPO="$1" WORKLOG_SKILL_BIN="$2" ENV_SECRETS=/nonexistent \
    AWS_CANON=/nonexistent AWS_SSO_CACHE='' VAULT_STAMP="$TMP/stamp" \
    bash "$SCRIPT" >"$TMP/out" 2>&1
}
mkdir -p "$TMP/home"

# 1. A clone with no worklog hooks: repaired through the chain, and announced.
V="$TMP/vault"; git init -q "$V"
run "$V" "$SKILL_BIN"
for h in pre-commit commit-msg post-commit pre-commit-identity; do
  [ "$(readlink "$V/.git/hooks/$h")" = "$SKILL_BIN/git-hooks/$h" ] || note "case 1: $h not linked"
done
grep -q "installed worklog git hooks in $V" "$TMP/out" || note "case 1: the repair was not announced"

# 2. Already hooked: no repair, no announcement.
run "$V" "$SKILL_BIN"
grep -q 'worklog git hooks' "$TMP/out" && note "case 2: a hooked clone was repaired again"

# 3. Opt-out: an empty WORKLOG_HOOKS_REPO touches nothing.
V3="$TMP/vault3"; git init -q "$V3"
run "" "$SKILL_BIN"
[ -e "$V3/.git/hooks/pre-commit" ] && note "case 3: opt-out still installed hooks"
grep -q 'worklog git hooks' "$TMP/out" && note "case 3: opt-out still reported"

# 4. Installer unavailable: loud, names the clone and the command, no false claim.
run "$V3" "$TMP/no-such-bin"
grep -q "worklog git hooks MISSING in $V3" "$TMP/out" || note "case 4: a failed repair was not reported"
grep -q 'installed worklog git hooks' "$TMP/out" && note "case 4: claimed an install that did not happen"

# 5. Only the identity link missing (a clone hooked before it was chained):
#    still repaired, since pre-commit alone skips the identity gate silently.
rm -f "$V/.git/hooks/pre-commit-identity"
run "$V" "$SKILL_BIN"
[ -L "$V/.git/hooks/pre-commit-identity" ] || note "case 5: a missing identity link was not repaired"

[ "$fails" -eq 0 ] || { echo "--- last output ---"; cat "$TMP/out"; exit 1; }
echo "ok: SessionStart repairs missing worklog hooks, quietly when hooked, loudly when it cannot"
