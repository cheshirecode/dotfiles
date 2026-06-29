#!/usr/bin/env bash
# Single-shot context pack for one task: frontmatter + recent commits
# + PR states + next. Read-only. Default shape: resume (for picking work back up);
# --for=review emits a reviewer-shaped pack.
#
# Usage:
#   bin/context.sh <slug>
#   bin/context.sh <slug> --for=review
#   bin/context.sh <slug> --format=json

set -euo pipefail

SLUG=""
FOR="resume"
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --for=*)    FOR="${1#--for=}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --for)      FOR="$2"; shift ;;
    --format)   FORMAT="$2"; shift ;;
    -h|--help)
      cat <<EOF
usage: context.sh <slug> [--for=resume|review|compact] [--format=markdown|json]
  --for=resume   (default) frontmatter + last 5 commits + open PRs + next
  --for=review   reviewer pack: frontmatter + PRs with state + context summary
  --for=compact  minimal resume kernel for post-/compact sessions (<20 lines)
EOF
      exit 0
      ;;
    *) SLUG="$1" ;;
  esac
  shift
done

if [[ -z "$SLUG" ]]; then
  echo "context: slug required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
LDAP="$(resolve_ldap)"

FILE="people/$LDAP/active/$SLUG.md"
[[ -f "$FILE" ]] || FILE="people/$LDAP/archive/$SLUG.md"
if [[ ! -f "$FILE" ]]; then
  matches=()
  while IFS= read -r match; do
    matches+=("$match")
  done < <(find people -path "*/active/$SLUG.md" -o -path "*/archive/$SLUG.md" | sort)
  if [[ ${#matches[@]} -eq 1 ]]; then
    FILE="${matches[0]}"
  elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "context: $SLUG is ambiguous across namespaces:" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  else
    echo "context: $SLUG not found under people/*/{active,archive}/" >&2
    exit 1
  fi
fi

# Commit history for this slug (follows renames via Worklog-Previous-Slug).
COMMITS="$(git log --all --format='%h%x1f%ad%x1f%s%x1f%b%x1e' --date=short \
  --grep="^${SLUG}:" --grep="Worklog-Slug: ${SLUG}" \
  --grep="Worklog-Previous-Slug: ${SLUG}\$" --regexp-ignore-case \
  -n 20 || true)"

echo "$COMMITS" | python3 "$SCRIPT_DIR/_context.py" \
  "$SLUG" "$FOR" "$FORMAT" "$FILE"
