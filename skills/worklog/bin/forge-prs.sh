#!/usr/bin/env bash
# forge-prs.sh — forge-aware PR/MR lookup for the `init` light-path drift check.
#
# The light path used to hardcode `gh pr list --author @me`. On a machine whose
# clones are GitLab (or where `gh` is not installed) that command emits nothing,
# so the `drift:` block rendered empty and *looked* clean. This script picks the
# CLI per clone from its origin remote and, when the needed CLI is missing or
# unauthenticated, emits an explicit `gap` row naming the repo it could not
# check. It never exits silently empty.
#
# Usage:
#   bin/forge-prs.sh list [--author <name>] [<clone-dir> ...]
#   bin/forge-prs.sh state <clone-dir> <number>
#
# `list` output (TSV, one row per finding):
#   open  <forge>  <owner/repo>  <number>  <url>  <title>
#   gap   <forge>  <owner/repo>  <reason>
#
# `state` output: one of  open | merged | closed | unknown
#   (exit 3 with a `gap` row on stderr when the forge CLI is unavailable)
#
# With no dirs, scans $PROJECTS_DIR/*/.

set -uo pipefail

emit_gap() { printf 'gap\t%s\t%s\t%s\n' "$1" "$2" "$3"; }

# github.com/o/r, git@github.com:o/r.git, ssh://git@gitlab.com/o/r.git → forge + slug
classify_remote() {
  local url="$1" host path
  url="${url%.git}"
  case "$url" in
    *://*) host="${url#*://}"; host="${host#*@}"; path="${host#*/}"; host="${host%%/*}" ;;
    *:*)   host="${url%%:*}"; host="${host#*@}"; path="${url#*:}" ;;
    *)     printf 'unknown\t\n'; return ;;
  esac
  host="${host%%:*}"
  local forge=unknown
  case "$host" in
    github.com|github.*) forge=github ;;
    gitlab.com|gitlab.*) forge=gitlab ;;
  esac
  printf '%s\t%s\n' "$forge" "$path"
}

# Per-forge auth probe, memoized: prints empty on success, a reason on failure.
GH_AUTH_REASON=""; GH_AUTH_DONE=""
GLAB_AUTH_REASON=""; GLAB_AUTH_DONE=""
forge_unavailable() {
  case "$1" in
    github)
      if [[ -z "$GH_AUTH_DONE" ]]; then
        GH_AUTH_DONE=1
        if ! command -v gh >/dev/null 2>&1; then
          GH_AUTH_REASON="gh-not-installed"
        elif ! gh auth status >/dev/null 2>&1; then
          GH_AUTH_REASON="gh-not-authenticated"
        fi
      fi
      printf '%s' "$GH_AUTH_REASON" ;;
    gitlab)
      if [[ -z "$GLAB_AUTH_DONE" ]]; then
        GLAB_AUTH_DONE=1
        if ! command -v glab >/dev/null 2>&1; then
          GLAB_AUTH_REASON="glab-not-installed"
        elif ! glab auth status >/dev/null 2>&1; then
          GLAB_AUTH_REASON="glab-not-authenticated"
        fi
      fi
      printf '%s' "$GLAB_AUTH_REASON" ;;
    *) printf 'unsupported-forge' ;;
  esac
}

# glab has no `@me`; resolve the authenticated username once.
GLAB_USER=""; GLAB_USER_DONE=""
glab_username() {
  if [[ -z "$GLAB_USER_DONE" ]]; then
    GLAB_USER_DONE=1
    GLAB_USER="${WORKLOG_GITLAB_USER:-}"
    [[ -z "$GLAB_USER" ]] && GLAB_USER="$(glab api user 2>/dev/null | jq -r '.username // empty' 2>/dev/null)"
  fi
  printf '%s' "$GLAB_USER"
}

urlencode_slug() { printf '%s' "$1" | sed 's|/|%2F|g'; }

cmd_list() {
  local author=""
  local -a dirs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --author=*) author="${1#--author=}" ;;
      --author)   author="${2:-}"; shift ;;
      -*) echo "forge-prs.sh list: unknown flag: $1" >&2; return 2 ;;
      *) dirs+=("$1") ;;
    esac
    shift
  done

  if [[ ${#dirs[@]} -eq 0 ]]; then
    local pd="${PROJECTS_DIR:-}"
    if [[ -z "$pd" || ! -d "$pd" ]]; then
      emit_gap none "-" "no-clones-discovered:PROJECTS_DIR-unset-or-missing"
      return 0
    fi
    local d
    for d in "$pd"/*/; do [[ -d "$d" ]] && dirs+=("${d%/}"); done
  fi

  if [[ ${#dirs[@]} -eq 0 ]]; then
    emit_gap none "-" "no-clones-discovered"
    return 0
  fi

  # Two clones of one project (a worktree-style sibling checkout, e.g.
  # midas and midas-wt-mockfix) would otherwise query it twice and report every
  # MR twice, which reads as drift that is not there. Plain string, not an
  # associative array: macOS ships Bash 3.
  local dir url forge slug reason user rows seen=""
  for dir in "${dirs[@]}"; do
    url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || continue
    [[ -z "$url" ]] && continue
    IFS=$'\t' read -r forge slug <<<"$(classify_remote "$url")"
    if [[ "$forge" == unknown || -z "$slug" ]]; then
      emit_gap unknown "${slug:-$dir}" "unrecognized-forge-host"
      continue
    fi
    case " $seen " in *" $forge/$slug "*) continue ;; esac
    seen="$seen $forge/$slug"
    reason="$(forge_unavailable "$forge")"
    if [[ -n "$reason" ]]; then
      emit_gap "$forge" "$slug" "$reason"
      continue
    fi
    case "$forge" in
      github)
        rows="$(gh pr list --author "${author:-@me}" --state open --limit 20 \
                  --json number,title,url -R "$slug" 2>/dev/null \
                | jq -r --arg f github --arg s "$slug" \
                    '.[] | ["open",$f,$s,(.number|tostring),.url,.title] | @tsv' 2>/dev/null)"
        if [[ -z "$rows" ]]; then
          gh pr list --author "${author:-@me}" --state open --limit 1 -R "$slug" >/dev/null 2>&1 \
            || emit_gap github "$slug" "gh-query-failed"
        fi
        [[ -n "$rows" ]] && printf '%s\n' "$rows"
        ;;
      gitlab)
        user="$author"; [[ -z "$user" ]] && user="$(glab_username)"
        if [[ -z "$user" ]]; then
          emit_gap gitlab "$slug" "glab-username-unresolved"
          continue
        fi
        rows="$(glab mr list --author="$user" -P 20 -F json -R "$slug" 2>/dev/null \
                | jq -r --arg f gitlab --arg s "$slug" \
                    '.[] | ["open",$f,$s,(.iid|tostring),(.web_url // ""),(.title // "")] | @tsv' 2>/dev/null)"
        if [[ -z "$rows" ]]; then
          glab mr list --author="$user" -P 1 -F json -R "$slug" >/dev/null 2>&1 \
            || emit_gap gitlab "$slug" "glab-query-failed"
        fi
        [[ -n "$rows" ]] && printf '%s\n' "$rows"
        ;;
    esac
  done
}

cmd_state() {
  local dir="${1:-}" num="${2:-}"
  [[ -z "$dir" || -z "$num" ]] && { echo "usage: forge-prs.sh state <clone-dir> <number>" >&2; return 2; }
  num="${num#\#}"; num="${num#!}"
  local url forge slug reason raw
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)"
  if [[ -z "$url" ]]; then
    emit_gap unknown "$dir" "no-origin-remote" >&2
    echo unknown; return 3
  fi
  IFS=$'\t' read -r forge slug <<<"$(classify_remote "$url")"
  if [[ "$forge" == unknown || -z "$slug" ]]; then
    emit_gap unknown "${slug:-$dir}" "unrecognized-forge-host" >&2
    echo unknown; return 3
  fi
  reason="$(forge_unavailable "$forge")"
  if [[ -n "$reason" ]]; then
    emit_gap "$forge" "$slug" "$reason" >&2
    echo unknown; return 3
  fi
  case "$forge" in
    github)
      # jq on the object's own key: a regex over the raw payload can match a
      # nested author.state instead (see CLAUDE.md § Test discipline).
      raw="$(gh pr view "$num" -R "$slug" --json state 2>/dev/null | jq -r '.state // empty' 2>/dev/null)" ;;
    gitlab)
      raw="$(glab api "projects/$(urlencode_slug "$slug")/merge_requests/$num" 2>/dev/null | jq -r '.state // empty' 2>/dev/null)" ;;
  esac
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    open|opened|reopened) echo open ;;
    merged)               echo merged ;;
    closed|locked)        echo closed ;;
    "") emit_gap "$forge" "$slug" "state-query-failed:$num" >&2; echo unknown; return 3 ;;
    *)  echo unknown; return 3 ;;
  esac
}

case "${1:-}" in
  list)  shift; cmd_list "$@" ;;
  state) shift; cmd_state "$@" ;;
  -h|--help|"") sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "forge-prs.sh: unknown subcommand: $1" >&2; exit 2 ;;
esac
