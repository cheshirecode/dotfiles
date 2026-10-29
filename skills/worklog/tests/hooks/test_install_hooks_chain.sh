#!/usr/bin/env bash
# In CHAIN mode (an outer core.hooksPath, as on Coder) install-hooks.sh links
# the worklog hooks into .git/hooks/, and the outer pre-commit execs
# .git/hooks/pre-commit. That hook finds pre-commit-identity next to its own
# path WITHOUT resolving the link, so the identity hook must be linked there
# too; otherwise the gate is skipped silently and a commit under another
# vault's domain lands. Seen on a Coder worklog clone, 2026-10-07.

set -uo pipefail

SKILL_BIN="$(cd "$(dirname "$0")/../../bin" && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-hooks-chain.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# Outer hooks dir standing in for a platform scanner: it only hands over to the
# repo's own .git/hooks/pre-commit, the way run_existing_hook.sh does.
mkdir -p "$TMP/outer"
cat > "$TMP/outer/pre-commit" <<'EOF'
#!/usr/bin/env bash
h="$(git rev-parse --git-dir)/hooks/pre-commit"
[ -x "$h" ] && exec "$h"
exit 0
EOF
chmod +x "$TMP/outer/pre-commit"
printf '[core]\n\thooksPath = %s\n' "$TMP/outer" > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=fixture@example.invalid

V="$TMP/vault"
git init -q "$V"
out="$(bash "$SKILL_BIN/install-hooks.sh" --data-root="$V" --write --git-hooks-only 2>&1)" ||
  note "install-hooks exited non-zero: $out"
printf '%s' "$out" | grep -q 'chained' || note "install-hooks did not take chain mode: $out"

for h in pre-commit commit-msg post-commit pre-commit-identity; do
  [ "$(readlink "$V/.git/hooks/$h")" = "$SKILL_BIN/git-hooks/$h" ] ||
    note "$h not linked into .git/hooks"
done
[ -z "$(git -C "$V" config --local --get core.hooksPath)" ] ||
  note "a repo-local core.hooksPath now shadows the outer scanner"

# The behaviour that matters: through the chain, a wrong-domain commit is
# refused. WORKLOG_NO_HOOK skips the lint gates, which run after identity.
echo x > "$V/a.md"; git -C "$V" add a.md
( cd "$V" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=someone@example-work.invalid \
    WORKLOG_IDENTITY_DOMAIN=users.noreply.github.com WORKLOG_NO_HOOK=1 \
    git commit -q -m wrong-domain >/dev/null 2>&1 )
git -C "$V" log --oneline -1 2>/dev/null | grep -q wrong-domain &&
  note "a commit under the wrong domain landed through the chain"

# Uninstall removes every link it made, the identity link included.
bash "$SKILL_BIN/install-hooks.sh" --data-root="$V" --uninstall --write --git-hooks-only >/dev/null 2>&1
for h in pre-commit commit-msg post-commit pre-commit-identity; do
  [ -L "$V/.git/hooks/$h" ] && note "uninstall left $h linked"
done

[ "$fails" -eq 0 ] || exit 1
echo "ok: chain mode links the identity hook, so the gate runs through the outer scanner"
