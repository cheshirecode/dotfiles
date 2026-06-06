#!/usr/bin/env bash
# Remove all `.cache/`-prefixed paths from `_worklog/main` history.
#
# Why: historical autosave commits committed `.cache/index.jsonl` (and other
# files under `.cache/`) before the directory was added to `.gitignore`. The
# files survive in git history forever; replaying them during a `git rebase`
# fails with "untracked working tree files would be overwritten" because the
# live working copy has the same path as a now-untracked file. This bit
# `bin/log-compact.sh --apply` twice on 2026-04-27 before being mitigated.
#
# This tool is the one-shot fix: rewrite history to drop every `.cache/`-
# prefixed blob, so future rebases (or anything else) don't trip on them.
# After this runs, `bin/log-compact.sh` doesn't need its `.cache/` stash dance.
#
# Usage:
#   bin/cache-purge.sh                # dry-run: report what would be purged
#   bin/cache-purge.sh --apply        # tag pre-cache-purge-<ts>, rewrite, push
#
# Safety:
#   - Refuses if working tree dirty / HEAD ahead of origin/main.
#   - Always tags pre-cache-purge-<timestamp> on `--apply`; pushed to origin.
#   - Uses git filter-repo --invert-paths --path .cache/ (battle-tested usage,
#     unlike the --commit-callback approach that bit us before).
#
# Single-user repo only. If _worklog/ ever gains a second active committer,
# don't run this — coordinate first.
#
# Requires: git-filter-repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "cache-purge: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "cache-purge: git-filter-repo not installed (try: brew install git-filter-repo)" >&2
  exit 2
fi

echo "=== Surveying .cache/ presence in history ==="
HITS="$(git log --all --diff-filter=A --name-only --format= -- '.cache/*' 2>/dev/null | sort -u | grep -v '^$' || true)"
COMMITS="$(git log --all --format='%H' -- '.cache/*' 2>/dev/null | sort -u | wc -l | tr -d ' ')"

if [[ -z "$HITS" ]]; then
  echo "cache-purge: .cache/ not present in history; nothing to do."
  exit 0
fi

echo "Files ever under .cache/ in history:"
printf '  %s\n' $HITS
echo ""
echo "Commits that touch .cache/: $COMMITS"
echo ""

if [[ "$APPLY" -eq 0 ]]; then
  echo "DRY RUN — re-run with --apply to rewrite history."
  echo "Note: --apply force-pushes main; tag pre-cache-purge-<ts> preserves the originals."
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "cache-purge: working tree dirty; commit or stash first" >&2
  exit 2
fi
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "cache-purge: untracked files present; commit or remove first" >&2
  exit 2
fi
HEAD_SHA="$(git rev-parse HEAD)"
ORIGIN_SHA="$(git rev-parse origin/main 2>/dev/null || echo "")"
if [[ -z "$ORIGIN_SHA" || "$HEAD_SHA" != "$ORIGIN_SHA" ]]; then
  echo "cache-purge: HEAD ($HEAD_SHA) != origin/main ($ORIGIN_SHA); fetch + push first" >&2
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
TAG="pre-cache-purge-${TS}"

echo "cache-purge: tagging $TAG"
git tag "$TAG"
git push origin "$TAG"

# Move .cache/ aside so filter-repo doesn't trip on the live untracked copy.
CACHE_BACKUP=""
if [[ -d .cache ]]; then
  CACHE_BACKUP="/tmp/cache-purge-backup-${TS}"
  mv .cache "$CACHE_BACKUP"
fi

echo "cache-purge: rewriting history via git filter-repo --invert-paths --path .cache/..."
# Capture origin URL because filter-repo removes 'origin' by default
# (safety measure; see https://github.com/newren/git-filter-repo/issues/46).
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo "")"
git filter-repo --force --invert-paths --path .cache/ 2>&1 | tail -5

# Restore .cache/ for the user.
if [[ -n "$CACHE_BACKUP" && -d "$CACHE_BACKUP" ]]; then
  mv "$CACHE_BACKUP" .cache
fi

# Re-add origin if filter-repo removed it; restore upstream tracking too.
if [[ -n "$ORIGIN_URL" ]] && ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$ORIGIN_URL"
  git fetch origin --quiet
fi

echo ""
echo "cache-purge: force-pushing main..."
# --force (not --force-with-lease) because the just-re-added origin doesn't
# have a "lease" reference to compare against. We verified HEAD == origin/main
# in the pre-flight, so --force is safe here. --set-upstream restores the
# tracking that filter-repo also stripped.
git push --force --set-upstream origin main

echo ""
echo "cache-purge: done."
echo "  - safety tag: $TAG (preserved on origin)"
echo "  - drop the tag with: git tag -d $TAG && git push --delete origin $TAG  (after a week of confidence)"
echo "  - run bin/post-rewrite-prompt.sh $TAG to print the cross-machine sync prompt for other clones"
