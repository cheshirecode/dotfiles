#!/usr/bin/env bash
# bin/git-hooks/pre-push: a remote marked private takes anything; every other
# remote is public and refuses a push whose commits carry a leak, including a
# leak added and removed inside the pushed range and one on a new branch.
# Runs in a disposable repo with two local bare remotes.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/prepush.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

# Same reason as test_leak_guard.sh: the author must come from this fixture,
# not from a developer's exported GIT_AUTHOR_EMAIL.
unset GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_NAME
git init -q -b main work && cd work || exit 1
git config user.email 1631630+cheshirecode@users.noreply.github.com
git config user.name cheshireCode
mkdir -p bin/git-hooks
cp "$REPO/bin/leak-guard.sh" bin/
cp "$REPO/bin/git-hooks/pre-push" bin/git-hooks/
git -c core.hooksPath=/dev/null add -A
git -c core.hooksPath=/dev/null commit -q -m seed
git config core.hooksPath bin/git-hooks
git init -q --bare "$TMP/pub.git"  && git remote add pub  "$TMP/pub.git"
git init -q --bare "$TMP/priv.git" && git remote add priv "$TMP/priv.git"
git config remote.priv.dotfiles-private true

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
remote_has() { [ "$(git --git-dir="$TMP/$1.git" rev-parse -q --verify "refs/heads/$2")" = "$(git rev-parse "$3")" ]; }
commit() { printf '%s\n' "$2" > "$1"; git add "$1"; git -c core.hooksPath=/dev/null commit -q -m "$1"; }

LEAK=ideogram   # pragma: allowlist owner

# 1. A clean history reaches the public remote, and the gate says it scanned.
git push -q pub main 2> out1 || note "refused a clean push to a public remote"
grep -q 'scanning [1-9]' out1 || note "the public gate did not report scanning anything, so nothing was tested"

# 2. A leaking commit is refused by the public remote, which stays where it was.
commit leak.md "org $LEAK-ai"
git push -q pub main 2>/dev/null && note "pushed a leaking commit to a public remote"
remote_has pub main HEAD~1 || note "the public remote moved despite the refusal"

# 3. The private remote takes the same history.
git push -q priv main 2>/dev/null || note "refused a push to a remote marked private"
remote_has priv main HEAD || note "the private remote did not receive the commit"

# 4. Removing the leak in a later commit does not launder the range.
git rm -q leak.md; git -c core.hooksPath=/dev/null commit -q -m unleak
git push -q pub main 2>/dev/null && note "pushed a range whose net diff is clean but whose history leaks"

# 5. A new branch has no remote sha; its commits are still scanned.
git checkout -q -b side main~2
commit side.md "org $LEAK-ai"
git push -q pub side 2>/dev/null && note "pushed a leaking new branch to a public remote"

# 6. A clean new branch from the published base still goes through.
git checkout -q -b clean main~2
commit ok.md "nothing notable"
git push -q pub clean 2>/dev/null || note "refused a clean new branch"

# 6b. Clean content under a leaking commit MESSAGE is refused: the message
#     publishes with the commit, and a diff-only scan never reads it. The
#     pragma, which exempts a content line, must not exempt a message line.
git checkout -q clean
echo "still nothing notable" > ok2.md; git add ok2.md
git -c core.hooksPath=/dev/null commit -q -m "port the fix from $LEAK-ai/ui  # pragma: allowlist owner"
git push -q pub clean 2>/dev/null && note "pushed a commit whose message leaks"
remote_has pub clean HEAD~1 || note "the public remote moved despite a leaking message"

# 7. Unmarking the private remote makes it public: the mark is opt-in.
git config --unset remote.priv.dotfiles-private
git checkout -q main
commit leak2.md "org $LEAK-ai"
git push -q priv main 2>/dev/null && note "an unmarked remote was treated as private"

[ "$fails" -eq 0 ] || exit 1
echo "ok: pre-push refuses leaks to public remotes (range, laundered and new-branch), passes clean pushes and private remotes"
