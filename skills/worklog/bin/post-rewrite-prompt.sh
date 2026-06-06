#!/usr/bin/env bash
# Print the canonical "history was force-pushed; sync your clone" prompt for
# pasting into other sessions or other-machine clones.
#
# Why: any tool in this repo that force-pushes main (`bin/log-compact.sh`,
# `bin/cache-purge.sh`, future history-rewrite tools) leaves other clones
# in a divergent state. The recovery is mechanical but easy to mess up.
# Templating the prompt removes the "did I write the right git command?"
# question every time.
#
# Usage:
#   bin/post-rewrite-prompt.sh                              # uses the most recent pre-* tag on origin
#   bin/post-rewrite-prompt.sh pre-squash-2026-04-27        # explicit safety tag/branch name
#   bin/post-rewrite-prompt.sh --reason="<short reason>"   # one-line context blurb
#
# Output goes to stdout — pipe it, copy-paste it, or redirect to a file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

REASON=""
TAG=""

for arg in "$@"; do
  case "$arg" in
    --reason=*) REASON="${arg#--reason=}" ;;
    --reason) shift; REASON="$1" ;;
    -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)
      if [[ -z "$TAG" ]]; then
        TAG="$arg"
      else
        echo "post-rewrite-prompt: unexpected arg: $arg" >&2; exit 2
      fi
      ;;
  esac
done

# Default tag: most recent pre-* on origin (covers pre-squash-*, pre-cache-purge-*, pre-compact-*).
if [[ -z "$TAG" ]]; then
  TAG="$(git ls-remote --tags origin 'pre-*' 2>/dev/null | awk '{print $2}' | sed 's|refs/tags/||' | sort -r | head -1)"
fi

if [[ -z "$TAG" ]]; then
  echo "post-rewrite-prompt: no pre-* safety tag found on origin; pass one explicitly" >&2
  exit 2
fi

REASON_LINE=""
if [[ -n "$REASON" ]]; then
  REASON_LINE=" ($REASON)"
fi

# Check whether the matching snapshot branch actually exists on origin.
# Some rewrite tools (bin/cache-purge.sh) only push the tag, not a branch.
# bin/log-compact.sh + manual user-created backups push both.
SNAPSHOT_REF=""
SNAPSHOT_LINE=""
RECOVERY_REF="refs/tags/${TAG}"
if git ls-remote --exit-code origin "refs/heads/${TAG}-snapshot" >/dev/null 2>&1; then
  SNAPSHOT_REF="${TAG}-snapshot"
  SNAPSHOT_LINE="
    branch: ${SNAPSHOT_REF}"
  RECOVERY_REF="refs/heads/${SNAPSHOT_REF}"
fi

cat <<EOF
The _worklog repo's main was history-rewritten on $(date +%Y-%m-%d)${REASON_LINE}. Tree content at HEAD is identical to before (verified by tree-fingerprint match) — only commit IDs changed. Sync this clone:

cd ~/Documents/projects/_worklog
git status                          # if dirty, commit-or-stash first
git fetch origin
git reset --hard origin/main        # adopts the rewritten main
git status                          # should be clean

Notes:
- If you had uncommitted work-in-progress: \`git stash\` first, then \`git stash pop\` after the reset. Conflicts likely if your changes touched the rewritten range; redo on top of new main.
- If you had local commits not yet pushed: still in your reflog (\`git reflog\`). Cherry-pick them onto the new main: \`git cherry-pick <sha>\`.
- Original pre-rewrite history preserved on origin at:
    tag:    $TAG${SNAPSHOT_LINE}
- Recovery if anything looks corrupted: \`git fetch origin && git reset --hard origin/${RECOVERY_REF}\`.
- Going forward: just keep using \`bin/checkpoint.sh\` as before. No further action needed.

For Claude / Codex / Cursor sessions, prepend: "_worklog history was force-pushed; sync this clone by:" then the block above.
EOF
