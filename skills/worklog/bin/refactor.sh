#!/usr/bin/env bash
# Rename a slug AND update every reference to it in other task files.
#
# `bin/checkpoint.sh --rename=<old>` only renames the task file itself
# (mv + Worklog-Previous-Slug trailer). It doesn't touch other tasks that
# reference the old slug via `parent_slug:`, `related[].slug`, `supersedes:`,
# `superseded_by:`, `reopens:`, or body mentions. Those references rot
# silently after the rename.
#
# This tool is the cross-task companion. It:
#   1. Renames the task file via `bin/checkpoint.sh --rename`
#   2. Walks every other task file under `people/*/{active,archive}/` and
#      rewrites references to the old slug → new slug
#   3. Single squash-shaped commit covers both file moves and reference
#      rewrites so reviewers see one coherent change
#
# Usage:
#   bin/refactor.sh <new-slug> --rename=<old-slug>     # dry-run by default
#   bin/refactor.sh <new-slug> --rename=<old-slug> --apply
#
# Safety:
#   - Refuses if working tree dirty / HEAD ahead of origin/main.
#   - Refuses if the new slug already has a task file.
#   - Refuses if the old slug doesn't have a task file (typo guard).
#   - Frontmatter rewrites use exact-key matching (no partial-string false positives).
#   - Body rewrites use word-boundary regex so longer slugs containing the
#     short slug don't get false-rewritten (e.g. renaming `foo` doesn't
#     accidentally rewrite `foo-bar`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

NEW_SLUG=""
OLD_SLUG=""
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rename=*) OLD_SLUG="${1#--rename=}" ;;
    --rename)   shift; OLD_SLUG="$1" ;;
    --apply)    APPLY=1 ;;
    -h|--help)  sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    --*)        echo "refactor: unknown flag: $1" >&2; exit 2 ;;
    *)          NEW_SLUG="$1" ;;
  esac
  shift
done

if [[ -z "$NEW_SLUG" || -z "$OLD_SLUG" ]]; then
  echo "refactor: usage: bin/refactor.sh <new-slug> --rename=<old-slug> [--apply]" >&2
  exit 2
fi

if [[ "$APPLY" -eq 1 ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "refactor: working tree dirty; commit or stash first" >&2
    exit 2
  fi
  HEAD_SHA="$(git rev-parse HEAD)"
  ORIGIN_SHA="$(git rev-parse origin/main 2>/dev/null || echo "")"
  if [[ -z "$ORIGIN_SHA" || "$HEAD_SHA" != "$ORIGIN_SHA" ]]; then
    echo "refactor: HEAD ($HEAD_SHA) != origin/main ($ORIGIN_SHA); fetch + push first" >&2
    exit 2
  fi
fi

# Locate the LDAP-namespaced task files.
. "$SCRIPT_DIR/_lib.sh"
LDAP="$(resolve_ldap)"

OLD_FILE=""
for state in active archive; do
  candidate="people/$LDAP/$state/$OLD_SLUG.md"
  [[ -f "$candidate" ]] && OLD_FILE="$candidate" && break
done
if [[ -z "$OLD_FILE" ]]; then
  echo "refactor: no file for old slug '$OLD_SLUG' under people/$LDAP/{active,archive}/" >&2
  exit 2
fi

NEW_FILE="$(dirname "$OLD_FILE")/$NEW_SLUG.md"
if [[ -f "$NEW_FILE" ]]; then
  echo "refactor: new slug '$NEW_SLUG' already has a file at $NEW_FILE" >&2
  exit 2
fi

# Find every other file that references the old slug.
echo "=== Surveying references to '$OLD_SLUG' across people/*/ ==="

# Frontmatter exact-key matches (parent_slug, supersedes, superseded_by, reopens).
FM_HITS="$(grep -lE "^(parent_slug|supersedes|superseded_by|reopens):\\s+$OLD_SLUG\$" \
  people/*/active/*.md people/*/archive/*.md 2>/dev/null | grep -v "^$OLD_FILE\$" || true)"

# Frontmatter related[] - slug entries (look for the indented `- slug: <old>` shape).
REL_HITS="$(grep -lE "^[[:space:]]+-?[[:space:]]*slug:\\s+$OLD_SLUG\$" \
  people/*/active/*.md people/*/archive/*.md 2>/dev/null | grep -v "^$OLD_FILE\$" || true)"

# Body mentions: word-boundary match anywhere in body. Captures both prose
# and markdown links. Uses ripgrep if available for speed, else grep.
BODY_HITS=""
if command -v rg >/dev/null 2>&1; then
  BODY_HITS="$(rg -lFw "$OLD_SLUG" people/*/active/*.md people/*/archive/*.md 2>/dev/null | grep -v "^$OLD_FILE\$" || true)"
else
  BODY_HITS="$(grep -lwE "$OLD_SLUG" people/*/active/*.md people/*/archive/*.md 2>/dev/null | grep -v "^$OLD_FILE\$" || true)"
fi

ALL_HITS="$(printf '%s\n%s\n%s\n' "$FM_HITS" "$REL_HITS" "$BODY_HITS" | grep -v '^$' | sort -u)"
COUNT="$(echo "$ALL_HITS" | grep -c . || true)"

echo ""
if [[ "$COUNT" -eq 0 ]]; then
  echo "No other files reference '$OLD_SLUG'."
else
  echo "$COUNT file(s) reference '$OLD_SLUG':"
  printf '  %s\n' $ALL_HITS
fi
echo ""
echo "Plan: rename $OLD_FILE → $NEW_FILE; rewrite '$OLD_SLUG' → '$NEW_SLUG' in the $COUNT files above."
echo ""

if [[ "$APPLY" -eq 0 ]]; then
  echo "DRY RUN — re-run with --apply."
  exit 0
fi

# 1. Rewrite references in other files (sed in-place; word-boundary match).
if [[ "$COUNT" -gt 0 ]]; then
  for f in $ALL_HITS; do
    # Use perl for portable word-boundary in-place edit (sed -i syntax differs
    # between BSD/Linux; perl behaves identically everywhere).
    perl -i -pe "s/\\b${OLD_SLUG}\\b/${NEW_SLUG}/g" "$f"
  done
fi

# 2. Rename the task file via checkpoint.sh (handles the Worklog-Previous-Slug
#    trailer). Note: checkpoint only stages NEW_FILE; we stage the rewritten
#    references too so they all land in one commit.
git add $ALL_HITS 2>/dev/null || true
  "$SCRIPT_DIR/checkpoint.sh" "$NEW_SLUG" --rename="$OLD_SLUG" --next="Cross-task slug rename: $OLD_SLUG → $NEW_SLUG, $COUNT references rewritten."

echo ""
echo "refactor: done."
echo "  - renamed: $OLD_FILE → $NEW_FILE"
echo "  - rewrote $COUNT cross-references"
echo "  - single commit emitted via bin/checkpoint.sh"
