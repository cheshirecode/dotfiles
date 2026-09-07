#!/usr/bin/env bash
# detect-forge.sh — name the forge behind a clone's origin remote, and say
# whether an authenticated CLI for it is available.
#
# Output (stdout, one line, always four tab-separated fields):
#   forge<TAB>slug<TAB>cli<TAB>reason
#
#   forge  : github | gitlab | other
#   slug   : owner/repo parsed from the remote URL
#   cli    : gh | glab | ""   (empty only when forge is "other")
#   reason : empty on success, otherwise one of
#            gh-not-installed, gh-not-authenticated,
#            glab-not-installed, glab-not-authenticated,
#            unsupported-forge-host
#
# Exit codes:
#   0 — forge recognized and its CLI is authenticated (reason is empty)
#   2 — usage error: bad flag, not a git repo, or no origin remote
#   3 — forge recognized but unusable; `reason` says why
#
# Exit 3 is deliberately distinct from 2. "I know this is GitLab and glab is
# missing" and "I cannot tell what this is" call for different fixes, and a
# caller that collapses them tells the user to install the wrong thing.
#
# Credentials, in order: --token wins; then GH_TOKEN/GITHUB_TOKEN (github) or
# GLAB_TOKEN/GITLAB_TOKEN (gitlab); then the CLI's own auth state.
#
# The CLI probe uses `gh auth status` / `glab auth status`, never `gh auth
# token`: the token subcommand prints the secret into a command substitution,
# and this script has no use for its value -- only for whether it exists.
#
# Usage:
#   detect-forge.sh [--repo <clone-dir>] [--token <value>]
#   # --repo omitted: uses the current directory's git root.
#
# Example output (a tab between each field):
#   github<TAB>acme/widget<TAB>gh<TAB>
#   gitlab	acme/gadget	glab	glab-not-installed

set -uo pipefail

PROG=${0##*/}

REPO_DIR=""
TOKEN_OVERRIDE=""

require_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "$PROG: $option requires a value" >&2
    exit 2
  fi
}

# Prints "forge<TAB>slug<TAB>cli". This runs in a command substitution, so it
# must RETURN the CLI rather than assign it: an earlier version set a global
# here and the assignment died with the subshell, leaving field 3 empty on
# every run while the header promised "gh".
classify_remote() {
  local url="$1" host path forge cli
  url="${url%.git}"
  case "$url" in
    *://*) host="${url#*://}"; host="${host#*@}"; path="${host#*/}"; host="${host%%/*}" ;;
    *:*)   host="${url%%:*}"; host="${host#*@}"; path="${url#*:}" ;;
    *)     printf 'unknown\t\t\n'; return ;;
  esac
  host="${host%%:*}"
  forge=other; cli=""
  case "$host" in
    github.com|*.github.com) forge=github; cli=gh ;;
    gitlab.com|*.gitlab.com) forge=gitlab; cli=glab ;;
  esac
  printf '%s\t%s\t%s\n' "$forge" "$path" "$cli"
}

# Prints a reason on failure, nothing on success.
auth_reason() {
  local forge="$1"

  # A caller-supplied token, or one already in the environment, answers the
  # question without probing. Both defaults are nested (${A:-${B:-}}); writing
  # ${A:-$B:-} instead yields the literal text "B:-", which is never empty, so
  # an absent CLI used to report success.
  local token=""
  if [[ -n "$TOKEN_OVERRIDE" ]]; then
    token="$TOKEN_OVERRIDE"
  else
    case "$forge" in
      github) token="${GH_TOKEN:-${GITHUB_TOKEN:-}}" ;;
      gitlab) token="${GLAB_TOKEN:-${GITLAB_TOKEN:-}}" ;;
    esac
  fi

  case "$forge" in
    github)
      command -v gh >/dev/null 2>&1 || { printf 'gh-not-installed'; return; }
      [[ -n "$token" ]] && return
      gh auth status >/dev/null 2>&1 || printf 'gh-not-authenticated'
      ;;
    gitlab)
      command -v glab >/dev/null 2>&1 || { printf 'glab-not-installed'; return; }
      [[ -n "$token" ]] && return
      glab auth status >/dev/null 2>&1 || printf 'glab-not-authenticated'
      ;;
    *)
      printf 'unsupported-forge-host'
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  require_value "$@"; REPO_DIR="$2"; shift 2 ;;
    --token) require_value "$@"; TOKEN_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "$PROG: not a git repository" >&2
    exit 2
  }
fi
[[ -n "$REPO_DIR" ]] || { echo "$PROG: not a git repository" >&2; exit 2; }

REMOTE_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)" || {
  echo "$PROG: could not resolve origin remote in $REPO_DIR" >&2
  exit 2
}
[[ -n "$REMOTE_URL" ]] || { echo "$PROG: origin remote points nowhere" >&2; exit 2; }

IFS=$'\t' read -r FORGE SLUG CLI <<<"$(classify_remote "$REMOTE_URL")"

if [[ "$FORGE" == "unknown" || "$FORGE" == "other" || -z "$SLUG" ]]; then
  printf 'other\t%s\t\tunsupported-forge-host\n' "${SLUG:-unrecognized}"
  exit 3
fi

REASON="$(auth_reason "$FORGE")"

printf '%s\t%s\t%s\t%s\n' "$FORGE" "$SLUG" "$CLI" "$REASON"
[[ -z "$REASON" ]] || exit 3
exit 0
