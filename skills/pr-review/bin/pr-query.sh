#!/usr/bin/env bash
# pr-query.sh — forge-agnostic PR/MR reads for the pr-review skill.
#
# Keeps every `gh` and `glab` invocation in one place so SKILL.md never has to
# hardcode a CLI. Read-only: nothing here edits, comments on, or merges a PR.
#
# Usage:
#   pr-query.sh view <number>      [--repo <dir>] [--token <val>]
#     → one JSON object: {number, title, isDraft, state, author:{login}, commits}
#       GitHub returns this natively; GitLab MR fields are mapped onto it.
#   pr-query.sh diff <number>      [--repo <dir>] [--token <val>]
#     → unified diff on stdout
#   pr-query.sh list-open [--author <name>] [--limit <N>] [--repo <dir>] [--token <val>]
#     → TSV: number  title  url  isDraft  author
#   pr-query.sh ci-status <number> [--repo <dir>] [--token <val>]
#     → TSV: check_name  status  conclusion  url
#   pr-query.sh merge-base         [--repo <dir>]
#     → the merge-base SHA against the default branch
#
# Exit codes:
#   0 — success
#   1 — the operation ran but the data was unusable (PR not found, no CI data)
#   2 — usage error, or the forge/CLI could not be resolved
#
# An empty stdout with exit 0 means "the forge returned nothing", which is a
# real answer. Capture the exit status before parsing: a failed call also
# produces no bytes, and the two are otherwise identical.
#
# "isDraft" is GitHub's field. GitLab uses a Draft/WIP title prefix, which is
# mapped to true/false here.
#
# Auth resolution is delegated to detect-forge.sh in this same directory.

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_DIR=""
TOKEN_VAL=""
OPERATION=""
NUMBER=""
AUTHOR=""
LIMIT="20"

require_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "$PROG: $option requires a value" >&2
    exit 2
  fi
}

usage() {
  echo "$PROG: usage: $PROG <view|diff|list-open|ci-status|merge-base> [<number>] [--repo <dir>] [--token <val>]" >&2
  exit 2
}

# The operation comes first, then its number if it takes one, then flags. An
# earlier version ran one loop over everything, so the positional number fell
# through to the `*)` arm: `view 7` exited 2 with "unknown argument: 7" and
# four of the five operations were unreachable.
[[ $# -gt 0 ]] || usage
case "$1" in
  view|diff|ci-status|list-open|merge-base) OPERATION="$1"; shift ;;
  *) echo "$PROG: unknown operation: $1" >&2; usage ;;
esac

case "$OPERATION" in
  view|diff|ci-status)
    [[ $# -gt 0 && "$1" != --* ]] || { echo "$PROG: $OPERATION requires a PR number" >&2; exit 2; }
    NUMBER="${1#\#}"; shift
    [[ "$NUMBER" =~ ^[0-9]+$ ]] || { echo "$PROG: PR number must be numeric, got '$NUMBER'" >&2; exit 2; }
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   require_value "$@"; REPO_DIR="$2"; shift 2 ;;
    --token)  require_value "$@"; TOKEN_VAL="$2"; shift 2 ;;
    --author) require_value "$@"; AUTHOR="$2"; shift 2 ;;
    --limit)  require_value "$@"; LIMIT="$2"; shift 2 ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- Resolve the forge -------------------------------------------------------
# merge-base is pure git and needs no forge, CLI, or credentials. Resolving one
# anyway would make it fail on an unauthenticated machine for no reason.
if [[ "$OPERATION" != "merge-base" ]]; then
  DET_ARGS=()
  [[ -n "$REPO_DIR" ]] && DET_ARGS+=(--repo "$REPO_DIR")
  [[ -n "$TOKEN_VAL" ]] && DET_ARGS+=(--token "$TOKEN_VAL")

  DET_OUTPUT="$("$SCRIPT_DIR/detect-forge.sh" ${DET_ARGS[@]+"${DET_ARGS[@]}"} 2>/dev/null)"
  IFS=$'\t' read -r FORGE SLUG CLI AUTH_REASON <<<"${DET_OUTPUT:-}"

  case "${FORGE:-}" in
    github|gitlab) ;;
    *) echo "$PROG: unsupported or unresolvable forge '${FORGE:-none}'" >&2; exit 2 ;;
  esac
  if [[ -n "${AUTH_REASON:-}" ]]; then
    echo "$PROG: $CLI unavailable for $FORGE ($AUTH_REASON)" >&2
    echo "$PROG: fix with '$CLI auth login', or pass --token <value>" >&2
    exit 2
  fi
  if [[ -n "$TOKEN_VAL" ]]; then
    case "$FORGE" in
      github) export GH_TOKEN="$TOKEN_VAL" ;;
      gitlab) export GLAB_TOKEN="$TOKEN_VAL" ;;
    esac
  fi
  GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
fi

# --- Helpers ----------------------------------------------------------------

glab_project_id() {
  glab api "projects/$(printf '%s' "$SLUG" | sed 's|/|%2F|g')" \
    --url "$GITLAB_URL" 2>/dev/null | jq -r '.id // empty'
}

repo_root() {
  if [[ -n "$REPO_DIR" ]]; then printf '%s' "$REPO_DIR"
  else git rev-parse --show-toplevel 2>/dev/null; fi
}

default_branch() {
  local dir="$1" remote_head
  remote_head="$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" \
    && { printf '%s' "$remote_head"; return; }
  git -C "$dir" show-ref --verify --quiet refs/remotes/origin/main \
    && { printf 'origin/main'; return; }
  git -C "$dir" show-ref --verify --quiet refs/remotes/origin/master \
    && { printf 'origin/master'; return; }
  git -C "$dir" show-ref --verify --quiet refs/heads/main && { printf 'main'; return; }
  git -C "$dir" show-ref --verify --quiet refs/heads/master && { printf 'master'; return; }
  printf 'main'
}

# --- Operations --------------------------------------------------------------

do_merge_base() {
  local dir base
  dir="$(repo_root)" || return 2
  [[ -n "$dir" ]] || { echo "$PROG: not a git repository" >&2; return 2; }
  base="$(default_branch "$dir")"
  git -C "$dir" merge-base "$base" HEAD 2>/dev/null || {
    echo "$PROG: no merge-base between $base and HEAD" >&2; return 1; }
}

do_view() {
  case "$FORGE" in
    github)
      gh pr view "$NUMBER" -R "$SLUG" \
        --json number,title,isDraft,state,author,commits 2>/dev/null || {
        echo "$PROG: PR #$NUMBER not found or inaccessible on $SLUG" >&2; return 1; }
      ;;
    gitlab)
      local pid raw
      pid="$(glab_project_id)"
      [[ -n "$pid" ]] || { echo "$PROG: could not resolve project id for $SLUG" >&2; return 1; }
      raw="$(glab api "projects/$pid/merge_requests/$NUMBER" --url "$GITLAB_URL" 2>/dev/null)" || {
        echo "$PROG: MR #$NUMBER not found or inaccessible on $SLUG" >&2; return 1; }
      # Build the object with jq, not printf: a title containing a quote or a
      # backslash would otherwise emit JSON that no consumer can parse.
      printf '%s' "$raw" | jq '{
        number:   .iid,
        title:    (.title // ""),
        isDraft:  ((.draft // .work_in_progress // false) == true),
        state:    ((.state // "unknown") | ascii_upcase),
        author:   {login: (.author.username // .author.name // "unknown")},
        commits:  []
      }' 2>/dev/null || { echo "$PROG: could not parse MR #$NUMBER" >&2; return 1; }
      ;;
  esac
}

do_diff() {
  case "$FORGE" in
    github)
      gh pr diff "$NUMBER" -R "$SLUG" 2>/dev/null || {
        echo "$PROG: could not fetch diff for PR #$NUMBER" >&2; return 1; }
      ;;
    gitlab)
      local pid
      pid="$(glab_project_id)"
      [[ -n "$pid" ]] || { echo "$PROG: could not resolve project id for $SLUG" >&2; return 1; }
      glab api "projects/$pid/merge_requests/$NUMBER/changes" --url "$GITLAB_URL" 2>/dev/null \
        | jq -r '.changes[]?.diff // empty' \
        || { echo "$PROG: could not fetch diff for MR #$NUMBER" >&2; return 1; }
      ;;
  esac
}

do_list_open() {
  case "$FORGE" in
    github)
      local who="${AUTHOR:-@me}"
      gh pr list -R "$SLUG" --author "$who" --state open --limit "$LIMIT" \
        --json number,title,url,isDraft,author 2>/dev/null \
        | jq -r '.[] | [(.number|tostring), .title, .url,
                        (if .isDraft then "true" else "false" end),
                        (.author.login // "")] | @tsv' \
        || { echo "$PROG: could not list open PRs on $SLUG" >&2; return 1; }
      ;;
    gitlab)
      local who="$AUTHOR"
      if [[ -z "$who" ]]; then
        who="$(glab api user --url "$GITLAB_URL" 2>/dev/null | jq -r '.username // empty')"
      fi
      [[ -n "$who" ]] || { echo "$PROG: list-open: no --author given and username unresolved" >&2; return 1; }
      local pid
      pid="$(glab_project_id)"
      [[ -n "$pid" ]] || { echo "$PROG: could not resolve project id for $SLUG" >&2; return 1; }
      glab api "projects/$pid/merge_requests?state=opened&author_username=$who&per_page=$LIMIT" \
        --url "$GITLAB_URL" 2>/dev/null \
        | jq -r '.[] | [(.iid|tostring), (.title // ""), (.web_url // ""),
                        (if ((.draft // .work_in_progress // false) == true) then "true" else "false" end),
                        (.author.username // .author.name // "")] | @tsv' \
        || { echo "$PROG: could not list open MRs on $SLUG" >&2; return 1; }
      ;;
  esac
}

do_ci_status() {
  case "$FORGE" in
    github)
      # `gh pr checks` exits non-zero when any check is failing -- that is a
      # verdict about the PR, not about this call, so its status is discarded
      # and the rows are what matter. An empty result falls through to the
      # rollup, which also covers PRs with no check runs at all.
      local rows
      rows="$(gh pr checks "$NUMBER" -R "$SLUG" --json name,state,link 2>/dev/null \
              | jq -r '.[] | [.name, .state, .state, (.link // "")] | @tsv')"
      if [[ -z "$rows" ]]; then
        rows="$(gh pr view "$NUMBER" -R "$SLUG" --json statusCheckRollup 2>/dev/null \
                | jq -r '.statusCheckRollup[]? | [(.name // .context // ""), (.status // .state // ""),
                                                  (.conclusion // .state // ""), (.detailsUrl // "")] | @tsv')"
      fi
      [[ -n "$rows" ]] || { echo "$PROG: no CI data for PR #$NUMBER" >&2; return 1; }
      printf '%s\n' "$rows"
      ;;
    gitlab)
      local pid sha rows
      pid="$(glab_project_id)"
      [[ -n "$pid" ]] || { echo "$PROG: could not resolve project id for $SLUG" >&2; return 1; }
      sha="$(glab api "projects/$pid/merge_requests/$NUMBER" --url "$GITLAB_URL" 2>/dev/null \
             | jq -r '.sha // empty')"
      [[ -n "$sha" ]] || { echo "$PROG: could not resolve head sha for MR #$NUMBER" >&2; return 1; }
      rows="$(glab api "projects/$pid/repository/commits/$sha/statuses" --url "$GITLAB_URL" 2>/dev/null \
              | jq -r '.[] | [(.name // ""), (.status // ""), (.status // ""), (.target_url // "")] | @tsv')"
      [[ -n "$rows" ]] || { echo "$PROG: no CI data for MR #$NUMBER" >&2; return 1; }
      printf '%s\n' "$rows"
      ;;
  esac
}

case "$OPERATION" in
  merge-base) do_merge_base ;;
  view)       do_view ;;
  diff)       do_diff ;;
  list-open)  do_list_open ;;
  ci-status)  do_ci_status ;;
esac
