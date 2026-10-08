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
# the task's `repos:` frontmatter, first entry, defaulting to example-repo.
#
# Exit: 0 nothing stale, 3 stale refs found, 1 usage or setup error.
# Exit 3 is a verdict, not an error — capture the output before parsing it, or
# `set -o pipefail` will report the verdict as a failure. See
# loop-engineering references/examples.md section 6.
#
# Degrades rather than blocking: with no token or no network every ref is
# reported `unchecked` and the exit stays 0. An unverifiable ref is not a
# passing ref, and saying so is the point. Each forge's credential is checked
# once first (GitLab /user, Jira /myself); a missing variable, a rejected
# credential or an unreachable host prints one note naming it, becomes the
# rows' reason, and skips that forge's remaining lookups.

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
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
# No default: a Jira host names a specific organisation and this repo is
# public. Supplied per installation, like WORKLOG_FORGE_NAMESPACE below, and
# an unset value is reported at the lookup rather than silently skipped.
JIRA_HOST="${JIRA_HOST:-}"

files=()
if [ -n "$SLUG" ]; then
  [ -f "$ACTIVE/$SLUG.md" ] || die "no active task: $SLUG"
  files=("$ACTIVE/$SLUG.md")
else
  while IFS= read -r f; do files+=("$f"); done < <(find "$ACTIVE" -name '*.md' | sort)
fi

# Positive control, once per forge, before the first lookup that needs it.
# Every per-ref failure collapses to `unchecked`, so without this a missing
# MCP_JIRA_EMAIL, a revoked token and a dead network all print the same row
# and nothing names the cause. Measured 2026-10-08: the email was absent from
# the shared secrets file, and every Jira ref read `unchecked` with no note.
# Runs in the main shell (not inside $(lookup)) so the verdict persists.
# Sets GL_WHY / JIRA_WHY: empty when the credential works, else the reason.
GL_READY=""; GL_WHY=""; JIRA_READY=""; JIRA_WHY=""
probe() {  # probe <url> <key> [curl auth args...] -> "" when <key> is in the JSON body
  local url=$1 key=$2 body rc; shift 2
  body=$(curl -sf --max-time 10 "$@" "$url" 2>/dev/null); rc=$?
  [ "$rc" = 0 ] || { [ "$rc" = 22 ] && echo "rejected (HTTP error)" || echo "unreachable (curl exit $rc)"; return; }
  printf '%s' "$body" | python3 -c 'import json,sys
try: sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)
except Exception: sys.exit(1)' "$key" || echo "answered without $key"
}
ready() {  # ready mr|issue
  if [ "$1" = mr ] && [ -z "$GL_READY" ]; then
    GL_READY=1
    if [ -z "$TOKEN" ]; then GL_WHY="GITLAB_TOKEN (or GITLAB_PAT) unset"
    else
      GL_WHY=$(probe "https://$GL_HOST/api/v4/user" id -H "PRIVATE-TOKEN: $TOKEN")
      [ -n "$GL_WHY" ] && GL_WHY="GitLab token check against $GL_HOST: $GL_WHY"
    fi
    [ -n "$GL_WHY" ] && echo "note: $GL_WHY; every MR ref is unchecked" >&2
  elif [ "$1" = issue ] && [ -z "$JIRA_READY" ]; then
    JIRA_READY=1
    local missing=""
    [ -n "$JIRA_TOKEN" ] || missing="$missing MCP_JIRA_API_TOKEN"
    [ -n "$JIRA_USER" ]  || missing="$missing MCP_JIRA_EMAIL"
    [ -n "$JIRA_HOST" ]  || missing="$missing JIRA_HOST"
    if [ -n "$missing" ]; then JIRA_WHY="unset:$missing"
    else
      JIRA_WHY=$(probe "https://$JIRA_HOST/rest/api/3/myself" accountId \
        -u "$JIRA_USER:$JIRA_TOKEN" -H "Accept: application/json")
      [ -n "$JIRA_WHY" ] && JIRA_WHY="Jira credential check against $JIRA_HOST: $JIRA_WHY"
    fi
    [ -n "$JIRA_WHY" ] && echo "note: $JIRA_WHY; every Jira ref is unchecked" >&2
  fi
  return 0
}

CACHE=$(mktemp); trap 'rm -f "$CACHE"' EXIT
ROWS=$(mktemp); trap 'rm -f "$CACHE" "$ROWS"' EXIT
NONS=$(mktemp); trap 'rm -f "$CACHE" "$ROWS" "$NONS"' EXIT
stale=0; live=0; unchecked=0

lookup() {  # lookup <kind> <ref> <project> -> prints state
  local key="$1|$2|$3" hit
  hit=$(grep -m1 -F "$key=" "$CACHE" 2>/dev/null) && { printf '%s' "${hit#*=}"; return; }
  local state="unchecked"
  if [ "$1" = mr ] && [ -z "$GL_WHY" ] && [ -n "$3" ]; then
    state=$(curl -sf --max-time 10 -H "PRIVATE-TOKEN: $TOKEN" \
      "https://$GL_HOST/api/v4/projects/$(printf '%s' "$3" | sed 's|/|%2F|g')/merge_requests/${2#!}" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["state"])
except Exception: print("")' 2>/dev/null) || state=""
    [ -z "$state" ] && state="unchecked"
  elif [ "$1" = issue ] && [ -z "$JIRA_WHY" ]; then
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
  # repos: comes in two YAML shapes and both are in active use. Reading only
  # the inline one silently defaulted every block-form task to example-repo: measured
  # 94 inline vs 62 block in one namespace, 15 of those block tasks naming a
  # different repo first. A wrong project 404s (loud, reported unchecked) —
  # but 4-digit MR numbers exist in several repos, so it can also return a
  # confident wrong state for an MR that merely shares an id.
  proj=$(awk '
    /^repos:[[:space:]]*\[/ {
      line = $0
      sub(/^repos:[[:space:]]*\[/, "", line)
      sub(/[],].*$/, "", line)
      gsub(/[\047"[:space:]]/, "", line)
      if (length(line)) { print line; exit }
      next
    }
    /^repos:[[:space:]]*$/ { inblock = 1; next }
    inblock && /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      gsub(/[\047"[:space:]]/, "", line)
      if (length(line)) { print line; exit }
      next
    }
    inblock && /^[^[:space:]#-]/ { inblock = 0 }
  ' "$f")
  # No repos: at all means the project is unknown, not example-repo. Guessing turns a
  # missing field into a confident verdict about some other repo's MR; an empty
  # proj skips the lookup and reports unchecked, which is a gap you can see.
  # (0 of 156 active tasks lack the field today, so this changes no current
  # result — it removes the way a future one could be silently wrong.)
  # A bare project name needs a forge namespace to become a lookup path. That
  # namespace is per-installation, supplied by WORKLOG_FORGE_NAMESPACE from the
  # per-clone .envrc: this repo is public, so no external namespace is committed
  # here. Unset leaves proj bare, which skips the lookup and reports unchecked
  # rather than guessing a namespace and returning a confident verdict about
  # somebody else's project.
  # proj_why names why proj is empty. It is the MR rows' reason, and the
  # namespace case is noted once per run at the end, listing only projects
  # whose refs were actually skipped: noting it per task printed 301 lines for
  # one project in a live run, burying the notes that mattered.
  proj_why=""
  case "$proj" in
    "") proj_why="task has no repos: field" ;;
    */*) ;;
    *) if [ -n "${WORKLOG_FORGE_NAMESPACE:-}" ]; then
         proj="$WORKLOG_FORGE_NAMESPACE/$proj"
       else
         proj_why="WORKLOG_FORGE_NAMESPACE unset, so '$proj' has no namespace"
         bare="$proj"; proj=""
       fi ;;
  esac
  # only unchecked items under ## Next
  items=$(awk '/^## Next/{n=1;next} /^## /{n=0} n' "$f" | grep -E '^\s*-\s*\[ \]' || true)
  [ -n "$items" ] || continue
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case "$ref" in
      !*) ready mr;    why=${GL_WHY:-${proj_why:-"the lookup failed"}};   st=$(lookup mr "$ref" "$proj")
          case "$proj_why" in WORKLOG_FORGE_NAMESPACE*) printf '%s\n' "$bare" >>"$NONS" ;; esac ;;
      *)  ready issue; why=${JIRA_WHY:-"the lookup failed"};                   st=$(lookup issue "$ref" "-") ;;
    esac
    case "$st" in
      merged|closed|done) printf 'stale|%s|%s|%s|%s\n' "$slug" "$ref" "$proj" "$st" >>"$ROWS"; stale=$((stale+1)) ;;
      unchecked)          printf 'unchecked|%s|%s|%s|%s\n' "$slug" "$ref" "$proj" "$why" >>"$ROWS"; unchecked=$((unchecked+1)) ;;
      *)                  live=$((live+1)) ;;
    esac
  done < <(printf '%s' "$items" | grep -ohE '![0-9]{3,5}|[A-Z]{2,6}-[0-9]+' | sort -u)
done

if [ -s "$NONS" ]; then
  echo "note: WORKLOG_FORGE_NAMESPACE unset; MR refs unchecked for $(sort -u "$NONS" | paste -sd, - | sed 's/,/, /g')" >&2
fi

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
