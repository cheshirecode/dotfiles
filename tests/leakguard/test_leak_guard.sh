#!/usr/bin/env bash
# bin/leak-guard.sh and its pre-commit hook: block identifiers and real home
# paths, allow placeholder paths, honour the bypass, and catch via --tree what
# --staged would have. Runs in a disposable repo.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leakguard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

git init -q . && git config user.email t@t.invalid && git config user.name t
# Repo-local user.email is NOT enough to decide the author: GIT_AUTHOR_EMAIL
# and friends override it, and this repo's own .envrc exports them. A shell
# with them set built a scratch history authored by the real identity, which
# is CLEAN, and the --authors assertions below then failed the guard for not
# flagging a dirty author that was never created. The guard was correct and
# the fixture was lying about what it had built.
#
# Unset them for the whole fixture so the author comes from the config above
# in every shell. Unsetting is right rather than exporting t@t.invalid: the
# sections that need a specific identity already pass it with `git -c`, and
# a test that silently depends on the developer's environment is the defect
# being removed here.
unset GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_NAME
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

# 7. An ambiguous owner name must block in ORG SHAPE only. The bare literal
#    hits 95 lines of superseded/supersedes/super() in this repo, and a guard
#    that noisy gets ignored -- so each shape is classified, and the English
#    word and the language keyword stay legal.
#
#    The fixtures are COMPOSED from $ORG rather than written out. A test
#    corpus containing the literal IS a match, so a spelled-out fixture makes
#    this file fail the very guard it tests. One pragma'd assignment, per the
#    "parameterise" rule in CLAUDE.md, keeps exactly one literal in the file.
ORG=super   # pragma: allowlist owner
# ${ORG^} is bash 4+; macOS ships bash 3.2, where it is a "bad substitution"
# that empties the array and reports "shapes[@]: unbound variable" instead.
ORG_CAP="$(printf '%s' "$ORG" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

shapes=(
  ". ~/.$ORG-autocomplete.bash"
  "$ORG extensions enable datadog"
  "if command -v $ORG >/dev/null; then"
  "# seed the file $ORG/hvac reads"
  "ADDR=https://vault.$ORG.net/v1"
  "# the same for everyone at $ORG_CAP"
)
for shape in "${shapes[@]}"; do
  git reset -q
  printf '%s\n' "$shape" > shape.md; git add shape.md
  git commit -q -m "shape-case" 2>/dev/null
  if committed shape-case; then
    note "committed an org-shaped owner reference: $shape"
    git reset -q --hard HEAD~1 2>/dev/null
  fi
done

# 8. ...and the benign forms must NOT block, in the same run. A guard that
#    blocks everything is as useless as one that blocks nothing.
git reset -q
cat > benign.md <<'BENIGN'
This decision supersedes the previous one, which was superseded in turn.
class E(Exception):
    def __init__(self): super().__init__("x")
A superficial change to a superset of the rows.
BENIGN
git add benign.md
git commit -q -m "benign-case" 2>/dev/null
committed benign-case || note "blocked superseded/super()/superset, which are not owner references"

# 9. An unambiguous owner literal added to OWNERS must block.
git reset -q
echo "vault-staging.private.staging.superinc.net" > host.md   # pragma: allowlist owner
git add host.md
git commit -q -m "host-case" 2>/dev/null
committed host-case && note "committed an internal hostname carrying an owner name"

# 10. A work REPO name must block too. 53 occurrences across 11 tracked files
#     had accumulated with nothing able to see them, because the list held
#     only orgs. Composed from $WREPO for the same reason as $ORG above: a
#     spelled-out fixture would make this file fail its own guard.
WREPO=midas   # pragma: allowlist owner
git reset -q
printf 'repos: [%s, monorepo]\n' "$WREPO" > repo.md; git add repo.md
git commit -q -m "repo-case" 2>/dev/null
committed repo-case && note "committed a work repo name"

# 11. --authors must flag a history that is not the project's noreply identity.
#     This scratch repo commits as t@t.invalid, so its whole history qualifies.
out="$(bash bin/leak-guard.sh --authors 2>&1)"; rc=$?
# Branch on rc explicitly. `[ "$rc" -eq 1 ] || note "accepted ..."` read every
# non-1 status as the guard having approved a dirty history — 127 for
# command-not-found, 2 for a usage error, a crash. A guard that could not run
# at all then reported as a guard that ran and passed, in the one mode whose
# job is catching a dirty identity. Seen for real: a harness that broke $0 so
# leak-guard.sh was not found produced "accepted a history ... (rc=127)" and
# sent someone hunting a defect that did not exist.
case "$rc" in
  1) ;;  # correct: refused
  0) note "--authors accepted a history authored by t@t.invalid" ;;
  *) note "--authors could not run (rc=$rc) — this is not a verdict, the guard did not execute: $(printf '%s' "$out" | head -1)" ;;
esac
printf '%s' "$out" | grep -q 't@t.invalid' || note "--authors did not name the offending address"

# 12. And it must PASS a history carrying only the project identity. A guard
#     that only ever fails certifies nothing, same as one that only ever passes.
CLEAN="$TMP/clean-authors"
git init -q "$CLEAN"
git -C "$CLEAN" -c user.email=1631630+cheshirecode@users.noreply.github.com \
    -c user.name=cheshireCode -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m clean-authors
( cd "$CLEAN" && bash "$TMP/bin/leak-guard.sh" --authors >/dev/null 2>&1 ) ||
  note "--authors rejected a history authored only by the project noreply identity"

# 13. A clean author with a dirty COMMITTER must still fail. A rewrite that
#     fixes %ae and forgets %ce is the exact shape this mode exists to catch.
git -C "$CLEAN" -c user.email=1631630+cheshirecode@users.noreply.github.com \
    -c user.name=cheshireCode -c committer.email=hidden@work-example.invalid \
    -c committer.name=hidden -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m committer-only
( cd "$CLEAN" && bash "$TMP/bin/leak-guard.sh" --authors >/dev/null 2>&1 ) &&
  note "--authors missed a dirty committer header while the author was clean"

[ "$fails" -eq 0 ] || exit 1
echo "ok: leak guard blocks identifiers, real home paths and org-shaped ambiguous names, allows placeholders and English/keyword uses, honours the bypass"
