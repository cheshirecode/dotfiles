#!/usr/bin/env bash
# Commit ONLY the named paths, then push, and refuse to push anything the commit
# did not create.
#
#   bin/safe-commit-push.sh <repo> <msgfile> <path> [<path>...]
#
# Why: `git commit ... ; git push` lies when a pre-commit hook rejects the
# commit -- the push still ships the unchanged prior commit and prints success.
# This checks that HEAD moved before pushing, merges upstream without rebasing
# (the worklog is shared; never `git pull --rebase`), and confirms the remote
# branch contains the new commit afterwards. Paths another session staged stay
# out of the commit.
#
# Exit status: 0 pushed or nothing to commit; 1 a step failed (the message says
# whether the commit is local only); 2 bad invocation.
set -uo pipefail
repo="${1:?usage: safe-commit-push.sh <repo> <msgfile> <path>...}"
msg="${2:?missing <msgfile>}"
shift 2
[ $# -gt 0 ] || { echo "REFUSED: name the paths to commit" >&2; exit 2; }
[ -s "$msg" ] || { echo "REFUSED: message file $msg is missing or empty" >&2; exit 2; }
cd "$repo" || exit 2

git add -- "$@" || { echo "FAILED: git add" >&2; exit 1; }
if git diff --cached --quiet -- "$@"; then
  echo "NOTHING TO COMMIT in: $*"; exit 0
fi
before=$(git rev-parse HEAD)
git commit -q --only -F "$msg" -- "$@" || { echo "FAILED: commit rejected; nothing pushed" >&2; exit 1; }
after=$(git rev-parse HEAD)
[ "$before" != "$after" ] || { echo "FAILED: HEAD did not move; nothing pushed" >&2; exit 1; }

git fetch -q || { echo "FAILED: fetch; committed $after locally, not pushed" >&2; exit 1; }
if ! git merge-base --is-ancestor '@{u}' HEAD; then
  # git merge refuses any staged change, even in a path the merge never
  # touches, so another session's staging blocks it. Say that, not "resolve".
  if ! git diff --cached --quiet; then
    echo "FAILED: upstream moved and other paths are staged ($(git diff --cached --name-only | tr '\n' ' ')); $after is local only -- push once they are committed" >&2
    exit 1
  fi
  git merge -q --no-edit '@{u}' || { echo "FAILED: merge with upstream; $after is local only -- resolve, then push" >&2; exit 1; }
fi
git push -q || { echo "FAILED: push; $after is local only" >&2; exit 1; }

git fetch -q
if git merge-base --is-ancestor "$after" '@{u}'; then
  echo "PUSHED $(git log --oneline -1 "$after")"
else
  echo "FAILED: upstream does not contain $after after push" >&2; exit 1
fi
