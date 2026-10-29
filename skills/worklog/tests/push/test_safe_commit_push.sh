#!/usr/bin/env bash
# bin/safe-commit-push.sh against a local bare remote: a commit a hook rejects
# must push nothing (a bare `commit; push` ships the prior HEAD and reports
# success), paths another session staged stay out, a peer's upstream commit is
# merged rather than rebased, and success means the remote holds the commit.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../../bin" && pwd -P)/safe-commit-push.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/safe-push.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name t
git config --global user.email t@example.invalid
git config --global init.defaultBranch main

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

git init -q --bare "$TMP/remote.git"
git clone -q "$TMP/remote.git" "$TMP/a" 2>/dev/null
( cd "$TMP/a" && echo base > base.md && git add base.md && git commit -qm base && git push -q -u origin main )
git clone -q "$TMP/remote.git" "$TMP/peer"
remote_head() { git --git-dir="$TMP/remote.git" rev-parse main; }
printf 'add one\n' > "$TMP/msg"

# 1. Named path only: a file another session staged is not swept in.
echo one > "$TMP/a/one.md"; echo other > "$TMP/a/other.md"; git -C "$TMP/a" add other.md
out="$(bash "$SCRIPT" "$TMP/a" "$TMP/msg" one.md 2>&1)" || note "case 1: exited non-zero: $out"
printf '%s' "$out" | grep -q '^PUSHED' || note "case 1: no PUSHED line"
git --git-dir="$TMP/remote.git" show --name-only --format= main | grep -qx one.md || note "case 1: one.md not on the remote"
git --git-dir="$TMP/remote.git" show --name-only --format= main | grep -qx other.md && note "case 1: a path another session staged was committed"
git -C "$TMP/a" diff --cached --name-only | grep -qx other.md || note "case 1: the other staged path lost its staging"

# 2. A hook rejects the commit: nothing pushed, and it says so.
before="$(remote_head)"
printf '#!/bin/sh\nexit 1\n' > "$TMP/a/.git/hooks/pre-commit"; chmod +x "$TMP/a/.git/hooks/pre-commit"
echo two > "$TMP/a/two.md"
bash "$SCRIPT" "$TMP/a" "$TMP/msg" two.md > "$TMP/out" 2>&1 && note "case 2: a rejected commit reported success"
grep -q 'commit rejected; nothing pushed' "$TMP/out" || note "case 2: the rejection was not reported"
[ "$(remote_head)" = "$before" ] || note "case 2: the remote moved after a rejected commit"
rm -f "$TMP/a/.git/hooks/pre-commit"

# 3a. A peer pushed first while another path is still staged here: git merge
#     refuses a staged index, so the commit stays local and the reason is named.
( cd "$TMP/peer" && git pull -q && echo p > peer.md && git add peer.md && git commit -qm peer && git push -q )
peer="$(git -C "$TMP/peer" rev-parse HEAD)"
bash "$SCRIPT" "$TMP/a" "$TMP/msg" two.md > "$TMP/out" 2>&1 && note "case 3a: reported success with upstream unmerged"
grep -q 'other paths are staged (other.md' "$TMP/out" || note "case 3a: the staged path was not named as the cause"
grep -q 'local only' "$TMP/out" || note "case 3a: did not say the commit is local only"
[ "$(remote_head)" = "$peer" ] || note "case 3a: the remote moved"
git -C "$TMP/a" rm -q --cached other.md

# 3b. Same peer push, clean index: merged, not rebased, both commits on the remote.
echo three > "$TMP/a/three.md"
bash "$SCRIPT" "$TMP/a" "$TMP/msg" three.md > "$TMP/out" 2>&1 || note "case 3b: exited non-zero: $(cat "$TMP/out")"
git --git-dir="$TMP/remote.git" merge-base --is-ancestor "$peer" main || note "case 3b: the peer commit is not on the remote"
[ "$(git --git-dir="$TMP/remote.git" rev-list --merges --count main)" -ge 1 ] || note "case 3b: upstream was not merged (rebased?)"

# 4. Nothing changed in the named path: exit 0, no commit.
before="$(remote_head)"
out="$(bash "$SCRIPT" "$TMP/a" "$TMP/msg" one.md 2>&1)" || note "case 4: exited non-zero"
printf '%s' "$out" | grep -q 'NOTHING TO COMMIT' || note "case 4: no NOTHING TO COMMIT line"
[ "$(remote_head)" = "$before" ] || note "case 4: the remote moved"

# 5. Bad invocation: no paths, or an empty message, is refused with 2.
bash "$SCRIPT" "$TMP/a" "$TMP/msg" >/dev/null 2>&1; [ $? -eq 2 ] || note "case 5: no paths was not refused with 2"
: > "$TMP/empty"; bash "$SCRIPT" "$TMP/a" "$TMP/empty" one.md >/dev/null 2>&1; [ $? -eq 2 ] || note "case 5: an empty message was not refused with 2"

[ "$fails" -eq 0 ] || exit 1
echo "ok: safe-commit-push commits only named paths, never pushes a rejected commit, merges a peer's push"
