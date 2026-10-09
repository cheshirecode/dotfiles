#!/usr/bin/env bash
# Publish the clean commits of the private canonical branch to the public
# remote. See docs/two-upstreams.md.
#
#   publish-public.sh            dry run: classify and print the plan
#   publish-public.sh --apply    build the public tip in a scratch worktree, push it
#
# Options: --src <ref> (default origin/main), --remote <name> (default github),
#          --no-fetch.
#
# Plan, oldest first, over the commits `git cherry` says the public branch
# lacks (matched by patch-id, so a cherry-picked copy counts as published):
#   - While the public tip is an ancestor of the source, fast-forward through
#     the leading run of clean commits. Same hashes, no divergence.
#   - After the first private commit, cherry-pick each later clean commit onto
#     the public tip. From then on the two histories differ by design.
#   - A private commit is never published. A conflicting cherry-pick (a clean
#     commit that builds on a private one) aborts the whole run: nothing is
#     pushed, and the commit is named.
# The push goes through the normal pre-push gate, which scans it again.
#
# Exit: 0 published or nothing to do (or a clean dry run), 1 refused or
# conflicted, 2 usage or setup error.

set -uo pipefail

APPLY=0 SRC=origin/main REMOTE=github FETCH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --src) SRC="${2:?--src needs a ref}"; shift ;;
    --remote) REMOTE="${2:?--remote needs a name}"; shift ;;
    --no-fetch) FETCH=0 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "publish-public: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "publish-public: not in a git checkout" >&2; exit 2; }
cd "$ROOT" || exit 2
GUARD="$ROOT/bin/leak-guard.sh"
[ -x "$GUARD" ] || { echo "publish-public: $GUARD missing" >&2; exit 2; }
if [ "$(git config --bool --get "remote.$REMOTE.dotfiles-private" 2>/dev/null)" = true ]; then
  echo "publish-public: $REMOTE is marked private; refusing to treat it as the public remote" >&2
  exit 2
fi

if [ "$FETCH" = 1 ]; then
  git fetch -q "${SRC%%/*}" && git fetch -q "$REMOTE" || { echo "publish-public: fetch failed" >&2; exit 2; }
fi
PUB="$REMOTE/main"
git rev-parse -q --verify "$PUB^{commit}" >/dev/null || { echo "publish-public: $PUB does not resolve" >&2; exit 2; }
git rev-parse -q --verify "$SRC^{commit}" >/dev/null || { echo "publish-public: $SRC does not resolve" >&2; exit 2; }

clean() {  # clean <sha>: content, message and identities pass both scanners
  "$GUARD" --range "$1^..$1" >/dev/null 2>&1 || return 1
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks git --no-banner --log-level error --log-opts="$1^..$1" "$ROOT" >/dev/null 2>&1 || return 1
  fi
  return 0
}

# A while-read, not mapfile: macOS ships bash 3.2.
todo=()
while IFS= read -r c; do todo+=("$c"); done < <(git cherry "$PUB" "$SRC" | sed -n 's/^+ //p')
if [ "${#todo[@]}" = 0 ]; then
  echo "publish-public: $PUB already has every commit of $SRC (by patch-id); nothing to do"
  exit 0
fi

linear=0; git merge-base --is-ancestor "$PUB" "$SRC" && linear=1
ff="" picks=() private=0
for c in "${todo[@]}"; do
  subj="$(git log -1 --format='%h %s' "$c")"
  if [ "$(git log -1 --format=%p "$c" | wc -w)" -gt 1 ]; then
    echo "  MERGE    $subj (skipped: merges are not published)"; private=$((private + 1)); linear=0; continue
  fi
  if clean "$c"; then
    if [ "$linear" = 1 ]; then ff="$c"; echo "  ff       $subj"
    else picks+=("$c"); echo "  pick     $subj"; fi
  else
    echo "  PRIVATE  $subj (stays on ${SRC%%/*})"; private=$((private + 1)); linear=0
  fi
done

if [ -z "$ff" ] && [ "${#picks[@]}" = 0 ]; then
  echo "publish-public: nothing clean to publish ($private private)"
  exit 0
fi
echo "publish-public: plan: ${ff:+fast-forward $PUB to $(git rev-parse --short "$ff"), }${#picks[@]} cherry-pick(s), $private private kept back"
[ "$APPLY" = 1 ] || { echo "publish-public: dry run; pass --apply to publish"; exit 0; }

WT="$(mktemp -d "${TMPDIR:-/tmp}/publish-public.XXXXXX")"
cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"; }
trap cleanup EXIT
git worktree add -q --detach "$WT" "${ff:-$PUB}" || { echo "publish-public: worktree failed" >&2; exit 2; }
for c in "${picks[@]}"; do
  if ! git -C "$WT" -c core.hooksPath=/dev/null cherry-pick --allow-empty "$c" >/dev/null 2>&1; then
    git -C "$WT" cherry-pick --abort >/dev/null 2>&1
    echo "publish-public: CONFLICT cherry-picking $(git log -1 --format='%h %s' "$c")" >&2
    echo "  it likely builds on a private commit. Nothing was pushed." >&2
    exit 1
  fi
done
if git -C "$WT" push -q "$REMOTE" HEAD:refs/heads/main; then
  echo "publish-public: pushed $(git -C "$WT" rev-parse --short HEAD) to $REMOTE/main"
else
  echo "publish-public: push to $REMOTE refused; nothing published" >&2
  exit 1
fi
