#!/usr/bin/env bash
# verify-refs.sh — flag open `## Next` items that cite already-closed work.
#
# A resume pack reproduces `## Next` faithfully, including items naming MRs that
# merged weeks ago, and nothing notices. That is how a resuming session re-opens
# finished work. Observed 2026-08-28: a pack served three items citing merged
# MRs under a header commanding hydration.
#
# DELIBERATELY NOT IN THE RESUME PATH. `context.sh --for=resume` stays local and
# offline: it must work with a dead token and no network, because that is
# exactly when a session is trying to recover. This is the separate opt-in pass,
# run where a network call is already expected and a failure is survivable.
#
# `last_updated` does NOT substitute for this. It tracks the file and every
# checkpoint bumps it, while `## Next` rots per-section — so the more actively a
# task is maintained, the fresher it looks over stale items.
#
# Usage:
#   verify-refs.sh [--json] [<slug>]      # one task, or all active when omitted
#
# Scope: only UNCHECKED `- [ ]` items under `## Next`, only refs of the form
# !NNNN (merge request) and KEY-NNNN (Jira). The project for an MR comes from
# the task's `repos:` frontmatter, first entry, defaulting to midas.
#
# Exit: 0 nothing stale, 3 stale refs found, 1 usage or setup error.
# Exit 3 is a verdict, not an error — capture the output before parsing it, or
# `set -o pipefail` will report the verdict as a failure. See
# loop-engineering references/examples.md section 6.
#
# Degrades rather than blocking: with no token or no network every ref is
# reported `unchecked` and the exit stays 0. An unverifiable ref is not a
# passing ref, and saying so is the point.

set -uo pipefail
PROG=${0##*/}

FMT=text
for a in "$@"; do [ "$a" = "--json" ] && FMT=json && break; done
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037'; }
die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  [ "$FMT" = json ] && printf '{"error":"%s"}\n' "$(json_escape "$1")"
  exit 1
}

SLUG=""
while [ $# -gt 0 ]; do
  case $1 in
    --json) shift ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) [ -z "$SLUG" ] || die "only one slug accepted"; SLUG=$1; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
LDAP="$(resolve_ldap)"
ACTIVE="$REPO_ROOT/people/$LDAP/active"
[ -d "$ACTIVE" ] || die "no active dir: $ACTIVE"

TOKEN="${GITLAB_PAT:-${GITLAB_TOKEN:-}}"
JIRA_USER="${MCP_JIRA_EMAIL:-}"; JIRA_TOKEN="${MCP_JIRA_API_TOKEN:-}"
GL_HOST="${GITLAB_HOST:-gitlab.com}"
JIRA_HOST="${JIRA_HOST:-snaptravelinc.atlassian.net}"

files=()
if [ -n "$SLUG" ]; then
  [ -f "$ACTIVE/$SLUG.md" ] || die "no active task: $SLUG"
  files=("$ACTIVE/$SLUG.md")
else
  while IFS= read -r f; do files+=("$f"); done < <(find "$ACTIVE" -name '*.md' | sort)
fi

CACHE=$(mktemp); trap 'rm -f "$CACHE"' EXIT
ROWS=$(mktemp); trap 'rm -f "$CACHE" "$ROWS"' EXIT
stale=0; live=0; unchecked=0

lookup() {  # lookup <kind> <ref> <project> -> prints state
  local key="$1|$2|$3" hit
  hit=$(grep -m1 -F "$key=" "$CACHE" 2>/dev/null) && { printf '%s' "${hit#*=}"; return; }
  local state="unchecked"
  if [ "$1" = mr ] && [ -n "$TOKEN" ]; then
    state=$(curl -sf --max-time 10 -H "PRIVATE-TOKEN: $TOKEN" \
      "https://$GL_HOST/api/v4/projects/$(printf '%s' "$3" | sed 's|/|%2F|g')/merge_requests/${2#!}" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["state"])
except Exception: print("")' 2>/dev/null) || state=""
    [ -z "$state" ] && state="unchecked"
  elif [ "$1" = issue ] && [ -n "$JIRA_TOKEN" ] && [ -n "$JIRA_USER" ]; then
    state=$(curl -sf --max-time 10 -u "$JIRA_USER:$JIRA_TOKEN" -H "Accept: application/json" \
      "https://$JIRA_HOST/rest/api/3/issue/$2?fields=status" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["fields"]["status"]["statusCategory"]["key"])
except Exception: print("")' 2>/dev/null) || state=""
    [ -z "$state" ] && state="unchecked"
  fi
  printf '%s=%s\n' "$key" "$state" >> "$CACHE"
  printf '%s' "$state"
}

for f in "${files[@]}"; do
  slug=$(basename "$f" .md)
  proj=$(sed -n 's/^repos:[[:space:]]*\[\([^],]*\).*/\1/p' "$f" | head -1 | tr -d ' ')
  [ -z "$proj" ] && proj=midas
  case "$proj" in */*) ;; *) proj="textemma/$proj" ;; esac
  # only unchecked items under ## Next
  items=$(awk '/^## Next/{n=1;next} /^## /{n=0} n' "$f" | grep -E '^\s*-\s*\[ \]' || true)
  [ -n "$items" ] || continue
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      !*) kind=mr;    st=$(lookup mr "$ref" "$proj") ;;
      *)  kind=issue; st=$(lookup issue "$ref" "-") ;;
    esac
    case "$st" in
      merged|closed|done) printf 'stale|%s|%s|%s|%s\n' "$slug" "$ref" "$proj" "$st" >>"$ROWS"; stale=$((stale+1)) ;;
      unchecked)          printf 'unchecked|%s|%s|%s|%s\n' "$slug" "$ref" "$proj" "no token or unreachable" >>"$ROWS"; unchecked=$((unchecked+1)) ;;
      *)                  live=$((live+1)) ;;
    esac
  done < <(printf '%s' "$items" | grep -ohE '![0-9]{3,5}|[A-Z]{2,6}-[0-9]+' | sort -u)
done

if [ "$FMT" = json ]; then
  printf '{"stale":%s,"live":%s,"unchecked":%s,"rows":[' "$stale" "$live" "$unchecked"
  first=1
  while IFS='|' read -r act sl rf pr why; do
    [ $first = 1 ] || printf ','
    printf '{"status":"%s","slug":"%s","ref":"%s","project":"%s","detail":"%s"}' \
      "$act" "$(json_escape "$sl")" "$(json_escape "$rf")" "$(json_escape "$pr")" "$(json_escape "$why")"
    first=0
  done <"$ROWS" 2>/dev/null
  printf ']}\n'
else
  printf '%s  %s task(s)\n' "$PROG" "${#files[@]}"
  while IFS='|' read -r act sl rf pr why; do
    printf '%-9s %-40s %-9s %s\n' "$act" "$sl" "$rf" "$why"
  done <"$ROWS" 2>/dev/null
  printf '%s stale, %s live, %s unchecked\n' "$stale" "$live" "$unchecked"
fi

[ "$stale" -gt 0 ] && exit 3
exit 0
