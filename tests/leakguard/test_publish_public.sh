#!/usr/bin/env bash
# bin/publish-public.sh: publish only clean commits from the private branch.
#   1. not diverged, all clean -> fast-forward: the SAME hashes, no copies
#   2. a private commit lands  -> it stays back; a later clean one is
#                                 cherry-picked; the private content never
#                                 reaches the public tree
#   3. rerun                   -> nothing to do (patch-id sees the copy)
#   4. clean commit built on a private one -> conflict, nothing pushed
#   5. dry run                 -> never pushes
# Runs in a scratch repo with two local bare remotes and the real gate wired.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/publish-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unset GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_NAME
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.email 1631630+cheshirecode@users.noreply.github.com
git config --global user.name cheshireCode
git config --global init.defaultBranch main

git init -q --bare "$TMP/origin.git"; git init -q --bare "$TMP/github.git"
git init -q "$TMP/w" && cd "$TMP/w" || exit 1
mkdir -p bin/git-hooks
cp "$REPO/bin/leak-guard.sh" "$REPO/bin/publish-public.sh" bin/
cp "$REPO/bin/git-hooks/pre-push" bin/git-hooks/
git add -A && git -c core.hooksPath=/dev/null commit -q -m seed
git remote add origin "$TMP/origin.git"; git remote add github "$TMP/github.git"
git config remote.origin.dotfiles-private true
git config core.hooksPath bin/git-hooks
git push -q origin main && git push -q github main 2>/dev/null

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
commit() { printf '%s\n' "$2" > "$1"; git add "$1"; git -c core.hooksPath=/dev/null commit -q -m "$3"; git push -q origin main; }
pub() { git --git-dir="$TMP/github.git" rev-parse main; }
publish() { OUT=$(bin/publish-public.sh "$@" 2>&1); RC=$?; }
LEAK=ideogram   # pragma: allowlist owner

# 1. Not diverged: fast-forward, same hashes.
commit a.md "alpha" "add alpha"
commit b.md "beta" "add beta"
publish --apply
[ "$RC" = 0 ] || note "clean fast-forward exited $RC: $OUT"
[ "$(pub)" = "$(git rev-parse main)" ] || note "public main is not the private tip: the clean run was copied, not fast-forwarded"

# 5. Dry run: plans, never pushes.
commit c.md "gamma" "add gamma"
before="$(pub)"
publish
grep -q 'ff .*add gamma' <<<"$OUT" || note "dry run did not plan the fast-forward"
[ "$(pub)" = "$before" ] || note "dry run pushed"

# 2. A private commit stays back; the clean one after it is cherry-picked.
commit p.md "org $LEAK-ai" "add private notes"
commit d.md "delta" "add delta"
publish --apply
[ "$RC" = 0 ] || note "publish around a private commit exited $RC: $OUT"
grep -q 'PRIVATE .*add private notes' <<<"$OUT" || note "the private commit was not classified PRIVATE"
git fetch -q github
git cat-file -e github/main:d.md 2>/dev/null || note "the clean commit after the private one was not published"
git cat-file -e github/main:p.md 2>/dev/null && note "the private commit's content reached the public tree"
git log --format=%s github/main | grep -q 'add private notes' && note "the private commit reached the public history"
git cat-file -e github/main:c.md 2>/dev/null || note "the clean commit before the private one was not published"

# 3. Rerun: patch-id recognises the cherry-picked copy.
tip="$(pub)"
publish --apply
grep -q 'nothing' <<<"$OUT" || note "rerun did not report nothing to do: $OUT"
[ "$(pub)" = "$tip" ] || note "rerun pushed again"

# 4. A clean commit that edits the private file cannot apply: nothing pushed.
commit p.md "org $LEAK-ai and more" "extend private notes"
printf 'x\n' >> p.md; git add p.md; git -c core.hooksPath=/dev/null commit -q -m "touch notes"; git push -q origin main
publish --apply
[ "$RC" = 1 ] || note "a conflicting cherry-pick exited $RC, want 1"
grep -q 'CONFLICT .*touch notes' <<<"$OUT" || note "the conflicting commit was not named: $OUT"
[ "$(pub)" = "$tip" ] || note "a conflicted run still pushed"
[ "$(git worktree list | wc -l)" -eq 1 ] || note "the scratch worktree was left behind: $(git worktree list | tail -n +2)"

[ "$fails" -eq 0 ] || exit 1
echo "ok: publish-public fast-forwards when it can, keeps private commits back, cherry-picks after them, and pushes nothing on conflict"
