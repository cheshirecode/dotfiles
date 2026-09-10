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
TRACKER="none"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --for=*)    FOR="${1#--for=}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --tracker=*) TRACKER="${1#--tracker=}" ;;
    --tracker)  [[ $# -ge 2 ]] || { echo "context: --tracker requires a value" >&2; exit 2; }; TRACKER="$2"; shift ;;
    --for)      [[ $# -ge 2 ]] || { echo "context: --for requires a value" >&2; exit 2; }; FOR="$2"; shift ;;
    --format)   [[ $# -ge 2 ]] || { echo "context: --format requires a value" >&2; exit 2; }; FORMAT="$2"; shift ;;
    -h|--help)
      cat <<EOF
usage: context.sh <slug> [--for=resume|review|compact] [--format=markdown|json]
  --for=resume   (default) frontmatter + last 5 commits + open PRs + next
  --for=review   reviewer pack: frontmatter + PRs with state + context summary
  --for=compact  minimal resume kernel for post-/compact sessions (<20 lines)
  --tracker=none|claude|codex|cursor|all  resume tracker format (default: none)
EOF
      exit 0
      ;;
    --*) echo "context: unknown option $1" >&2; exit 2 ;;
    *) [[ -z "$SLUG" ]] || { echo "context: one slug required" >&2; exit 2; }; SLUG="$1" ;;
  esac
  shift
done

case "$FOR" in resume|review|compact) ;; *) echo "context: invalid --for" >&2; exit 2 ;; esac
case "$FORMAT" in markdown|json) ;; *) echo "context: invalid --format" >&2; exit 2 ;; esac
case "$TRACKER" in none|claude|codex|cursor|all) ;; *) echo "context: invalid --tracker" >&2; exit 2 ;; esac

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
HISTORY_LIMIT=20
[[ "$FOR" == "compact" ]] && HISTORY_LIMIT=1
COMMITS="$(git log --all --format='%h%x1f%ad%x1f%s%x1f%b%x1e' --date=short \
  --grep="^${SLUG}:" --grep="Worklog-Slug: ${SLUG}" \
  --grep="Worklog-Previous-Slug: ${SLUG}\$" --regexp-ignore-case \
  -n "$HISTORY_LIMIT" || true)"

echo "$COMMITS" | python3 "$SCRIPT_DIR/_context.py" \
  "$SLUG" "$FOR" "$FORMAT" "$FILE" "$TRACKER"
