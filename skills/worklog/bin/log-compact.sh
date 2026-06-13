#!/usr/bin/env bash
# Compact same-slug `<slug>: checkpoint` bursts in the worklog log into
# single squashed commits. Preserves the chronological next_action sequence
# in the new commit body.
#
# Usage:
#   bin/log-compact.sh                                # dry-run, all-time
#   bin/log-compact.sh --since=2026-04-01             # dry-run since date
#   bin/log-compact.sh --slug=responsive-image-...    # one-slug dry-run
#   bin/log-compact.sh --apply                        # rewrite + force-push
#
# Filters (all optional, AND-combined):
#   --slug=X            only bursts for slug X
#   --keyword=Y         only commits whose body matches /Y/
#   --since=DATE        only commits at or after DATE (e.g. 2026-04-01 or "1 week ago")
#   --until=DATE        only commits at or before DATE
#   --burst-window=Nh   max gap inside a burst (default 4h)
#   --min-burst=N       minimum burst size to compact (default 3)
#
# Modes:
#   (default)           dry-run: write plan to /tmp, exit 0
#   --apply             tag pre-compact-<timestamp>, rewrite, force-push
#
# Safety:
#   - Always tags HEAD before --apply ("pre-compact-<timestamp>") so original
#     SHAs remain reachable. Tag is also pushed to origin.
#   - Refuses to run with a dirty working tree.
#   - Refuses to run if HEAD != origin/main.
#   - Eligibility is exact `^<slug>: checkpoint$` — meaningful subjects
#     (post-Improvement-1) are never squashed.
#
# Requires: git-filter-repo (brew install git-filter-repo on macOS).
#
# See: people/cheshirecode/active/worklog-log-compaction-squash.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

SLUG=""
KEYWORD=""
SINCE=""
UNTIL=""
BURST_WINDOW="4h"
MIN_BURST=3
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug=*)          SLUG="${1#--slug=}" ;;
    --keyword=*)       KEYWORD="${1#--keyword=}" ;;
    --since=*)         SINCE="${1#--since=}" ;;
    --until=*)         UNTIL="${1#--until=}" ;;
    --burst-window=*)  BURST_WINDOW="${1#--burst-window=}" ;;
    --min-burst=*)     MIN_BURST="${1#--min-burst=}" ;;
    --apply)           APPLY=1 ;;
    -h|--help)
      sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "log-compact: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Pre-flight
if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "log-compact: git-filter-repo not installed (try: brew install git-filter-repo)" >&2
  exit 2
fi

if [[ "$APPLY" -eq 1 ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "log-compact: working tree dirty; commit or stash first" >&2
    exit 2
  fi
  if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "log-compact: untracked files present; commit or remove first" >&2
    exit 2
  fi
  HEAD_SHA="$(git rev-parse HEAD)"
  ORIGIN_SHA="$(git rev-parse origin/main 2>/dev/null || echo "")"
  if [[ -z "$ORIGIN_SHA" || "$HEAD_SHA" != "$ORIGIN_SHA" ]]; then
    echo "log-compact: HEAD ($HEAD_SHA) != origin/main ($ORIGIN_SHA); fetch + push first" >&2
    exit 2
  fi
  # 2026-04-27: previous filter-repo-based --apply path discarded 613 unrelated
  # commits' file changes. Replaced with `git rebase -i --root` + auto-generated
  # todo. New algorithm verified end-to-end in tests/log_compact/test_squash.sh
  # against a scratch clone of main BEFORE touching main itself.
fi

# Parse burst-window (Nh / Nm / Nd) into seconds
parse_window() {
  local raw="$1"
  local n="${raw%[hmd]}"
  local unit="${raw: -1}"
  case "$unit" in
    h) echo $((n * 3600)) ;;
    m) echo $((n * 60)) ;;
    d) echo $((n * 86400)) ;;
    *) echo "$raw" ;;
  esac
}
WINDOW_SEC="$(parse_window "$BURST_WINDOW")"

TS="$(date +%Y%m%d-%H%M%S)"
PLAN_FILE="/tmp/log-compact-plan-${TS}.md"
SIDECAR="/tmp/log-compact-bursts-${TS}.tsv"

LOG_ARGS=(--reverse --format=%H%x1f%aI%x1f%aN%x1f%s%x1f%b%x1e)
[[ -n "$SINCE" ]] && LOG_ARGS+=(--since="$SINCE")
[[ -n "$UNTIL" ]] && LOG_ARGS+=(--until="$UNTIL")

git log "${LOG_ARGS[@]}" \
  | python3 "$SCRIPT_DIR/_log_compact.py" "$SLUG" "$KEYWORD" "$WINDOW_SEC" "$MIN_BURST" "$PLAN_FILE" "$SIDECAR"

echo ""

if [[ "$APPLY" -eq 0 ]]; then
  echo "DRY RUN — review plan at $PLAN_FILE"
  echo "Re-run with --apply to rewrite history (will tag pre-compact-${TS} first)."
  exit 0
fi

# ---- APPLY ------------------------------------------------------------------
if [[ ! -s "$SIDECAR" ]]; then
  echo "log-compact: nothing to compact (sidecar empty)"
  exit 0
fi

TAG="pre-compact-${TS}"
echo "log-compact: tagging current HEAD as $TAG"
git tag "$TAG"
git push origin "$TAG"

# Generate the rebase todo + per-anchor message files.
TODO="/tmp/log-compact-todo-${TS}"
MSGS_DIR="/tmp/log-compact-msgs-${TS}"
echo "log-compact: generating rebase todo..."
python3 "$SCRIPT_DIR/_log_compact_apply.py" "$SIDECAR" "$TODO" "$MSGS_DIR"

# GIT_SEQUENCE_EDITOR is invoked once with the auto-generated todo; we replace
# it byte-for-byte with our own. GIT_EDITOR is invoked once per `reword`; we
# read the next pre-built message file based on a counter stored in MSGS_DIR.
SEQ_EDITOR_SHIM="/tmp/log-compact-seq-editor-${TS}.sh"
cat > "$SEQ_EDITOR_SHIM" <<EOF
#!/usr/bin/env bash
cp "$TODO" "\$1"
EOF
chmod +x "$SEQ_EDITOR_SHIM"

EDITOR_SHIM="/tmp/log-compact-editor-${TS}.sh"
cat > "$EDITOR_SHIM" <<EOF
#!/usr/bin/env bash
counter_file="$MSGS_DIR/counter"
n="\$(cat "\$counter_file")"
msg_file="\$(printf '%s/msg-%04d.txt' "$MSGS_DIR" "\$n")"
if [[ -f "\$msg_file" ]]; then
  cp "\$msg_file" "\$1"
fi
echo "\$((n + 1))" > "\$counter_file"
EOF
chmod +x "$EDITOR_SHIM"

echo "log-compact: rewriting history via git rebase -i --root..."
echo "  (this can take a minute; $(wc -l < "$TODO") commits to process)"

# .cache/ holds derived artifacts (index.jsonl, lint stamps, kernels). It's
# in .gitignore now, but historical autosave commits committed it before it
# was ignored. Replaying those during rebase fails with "untracked working
# tree files would be overwritten." Move it aside; restore after rebase.
CACHE_BACKUP=""
if [[ -d .cache ]]; then
  CACHE_BACKUP="/tmp/log-compact-cache-${TS}"
  mv .cache "$CACHE_BACKUP"
fi

# WORKLOG_NO_HOOK / WORKLOG_NO_LINT skip pre-commit / post-commit hooks during
# the rebase. Each rebase step is an intermediate state; running hooks on
# every one is slow AND a hook failure on a transient state pauses the rebase.
# Lint runs once on the final HEAD afterward (verified by test_squash.sh).
REBASE_STATUS=0
GIT_SEQUENCE_EDITOR="$SEQ_EDITOR_SHIM" GIT_EDITOR="$EDITOR_SHIM" \
  WORKLOG_NO_HOOK=1 WORKLOG_NO_LINT=1 \
  git rebase -i --root --committer-date-is-author-date 2>&1 | tail -5 \
  || REBASE_STATUS=$?

# Restore .cache/ even on failure so the user gets their cache back.
if [[ -n "$CACHE_BACKUP" && -d "$CACHE_BACKUP" ]]; then
  if [[ -d .cache ]]; then
    cp -R "$CACHE_BACKUP"/. .cache/ 2>/dev/null || true
    rm -rf "$CACHE_BACKUP"
  else
    mv "$CACHE_BACKUP" .cache
  fi
fi

if [[ "$REBASE_STATUS" -ne 0 ]]; then
  echo "log-compact: rebase exited non-zero ($REBASE_STATUS)" >&2
  echo "  recover with: git rebase --abort && git reset --hard $TAG" >&2
  exit "$REBASE_STATUS"
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "log-compact: rebase failed — HEAD is detached or rebase still in progress" >&2
  echo "  recover with: git rebase --abort && git reset --hard $TAG" >&2
  exit 3
fi

if [[ -d .cache ]]; then
  rm -f .cache/index.jsonl .cache/index.embeddings.jsonl \
    .cache/compact-kernels.md .cache/compact-kernels.json \
    .cache/cross-task.stamp
  echo "log-compact: invalidated derived caches after history rewrite"
  echo "  refresh with: $SCRIPT_DIR/index.sh && $SCRIPT_DIR/compact-kernels.sh"
  echo "  optional semantic refresh: $SCRIPT_DIR/embed.sh --refresh"
fi

echo ""
echo "log-compact: force-pushing main..."
git push --force-with-lease origin main

echo ""
echo "log-compact: done."
echo "  - safety tag: $TAG (preserved on origin)"
echo "  - plan file:  $PLAN_FILE"
echo "  - todo file:  $TODO"
echo "  - msgs dir:   $MSGS_DIR"
echo "  - drop the tag with: git tag -d $TAG && git push --delete origin $TAG  (only when confident)"
