#!/usr/bin/env bash
# prs.sh — list open PRs in $WORKLOG_GH_ORG org requesting review from the caller
# or their team(s), updated within the last N days.
#
# Usage: bin/prs.sh [--days N]   (default: 5)
#
# Output: tab-separated, grep/parse-friendly.
#   columns: number <TAB> state <TAB> author <TAB> updatedAt <TAB> repo <TAB> title <TAB> url
#   section headers start with "# "
#   first-match dedup: priority @me > team sections (alphabetical by slug)

set -euo pipefail

# Identity: which GitHub org to query. Per-clone via env, with fallback
# to the active git remote's owner. Hard-fail if neither resolves —
# refusing to silently query someone else's org.
if [[ -z "${WORKLOG_GH_ORG:-}" ]]; then
  WORKLOG_GH_ORG="$(gh repo view --json owner -q .owner.login 2>/dev/null || true)"
fi
if [[ -z "${WORKLOG_GH_ORG:-}" ]]; then
  echo "prs: set WORKLOG_GH_ORG (or run inside a clone with a gh-recognized remote)" >&2
  exit 1
fi

DAYS=5
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --days=*) DAYS="${1#--days=}"; shift ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

SINCE=$(date -d "${DAYS} days ago" +%Y-%m-%d 2>/dev/null \
     || date -v-"${DAYS}"d +%Y-%m-%d)

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG="$SCRIPT_DIR/../config/teams.json"
if [ ! -f "$CONFIG" ]; then
  echo "missing config: $CONFIG" >&2
  exit 1
fi

# Resolve caller's $WORKLOG_GH_ORG team slugs → approver filter slugs (deduped, sorted).
MEMBER_SLUGS=$(gh api /user/teams --paginate \
  --jq '.[] | select(.organization.login == "$WORKLOG_GH_ORG") | .slug' \
  2>/dev/null || true)

APPROVER_SLUGS=$(
  printf '%s\n' "$MEMBER_SLUGS" \
    | jq -R -s --slurpfile cfg "$CONFIG" '
        split("\n") | map(select(length > 0)) as $mine
        | $cfg[0] as $map
        | [ $mine[] | $map[.] // [] ] | add // []
        | unique | .[]
      '
)

TEMPLATE='{{range .}}{{.number}}	{{.state}}	{{.author.login}}	{{.updatedAt}}	{{.repository.nameWithOwner}}	{{.title}}	{{.url}}
{{end}}'
FIELDS='number,state,author,updatedAt,repository,title,url'

SEEN_FILE=$(mktemp); trap 'rm -f "$SEEN_FILE"' EXIT

emit_section() {
  local label="$1"; shift
  local rows
  rows=$(gh search prs --owner $WORKLOG_GH_ORG --state open --updated ">=$SINCE" \
    "$@" --json "$FIELDS" --template "$TEMPLATE" 2>/dev/null || true)
  [ -z "$rows" ] && return 0
  local filtered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local url; url=$(printf '%s' "$line" | awk -F'\t' '{print $NF}')
    if ! grep -qxF "$url" "$SEEN_FILE"; then
      filtered+="$line"$'\n'
      printf '%s\n' "$url" >> "$SEEN_FILE"
    fi
  done <<< "$rows"
  [ -z "$filtered" ] && return 0
  printf '# %s (since %s)\n' "$label" "$SINCE"
  printf '%s' "$filtered"
  printf '\n'
}

emit_section "review-requested: @me" --review-requested "@me"

printf '%s\n' "$APPROVER_SLUGS" | sort -u | while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  emit_section "team: $slug" --review-requested "$WORKLOG_GH_ORG/$slug"
done
