#!/usr/bin/env bash
# owner-check.sh — decide whether a PR/MR belongs to the current user.
#
# pr-review picks its mode from this answer: "self" runs a fast self-check that
# may edit in place, "other" runs an adversarial, report-only review. Guessing
# wrong in the "self" direction is the costly error -- it lets the skill edit
# someone else's PR -- so every failure below resolves to an error, never to a
# default of "self".
#
# Forge detection and auth resolution are delegated to detect-forge.sh.
#
# Usage:
#   owner-check.sh <pr-number> [--repo <clone-dir>] [--token <value>]
#   # <pr-number> may be written "N" or "#N".
#
# Output on stdout: "self" or "other". Nothing is printed on error.
#
# Exit 0 → self  (PR author, or a commit author, matches the current user)
# Exit 1 → other (author differs)
# Exit 2 → error (bad usage, forge unresolvable, no auth, PR inaccessible)
#
# Exit 1 is a verdict, not a failure. A caller running under `set -e` must
# capture the status rather than let the shell abort on "other".

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "$PROG: usage: $PROG <pr-number> [--repo <dir>] [--token <val>]" >&2
  exit 2
fi

PR_NUMBER="${1#\#}"
shift
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "$PROG: PR number must be numeric, got '$PR_NUMBER'" >&2; exit 2; }

REPO_DIR=""
TOKEN_VAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO_DIR="${2:-}"; shift 2 ;;
    --token) TOKEN_VAL="${2:-}"; shift 2 ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# --- Detect the forge --------------------------------------------------------
DET_ARGS=()
[[ -n "$REPO_DIR" ]] && DET_ARGS+=(--repo "$REPO_DIR")
[[ -n "$TOKEN_VAL" ]] && DET_ARGS+=(--token "$TOKEN_VAL")

DET_OUTPUT="$("$SCRIPT_DIR/detect-forge.sh" ${DET_ARGS[@]+"${DET_ARGS[@]}"} 2>/dev/null)"
IFS=$'\t' read -r FORGE SLUG CLI AUTH_REASON <<<"${DET_OUTPUT:-}"

# printf, not echo: bash's echo prints "\n" as two literal characters, so the
# multi-line hints below reached the user as one run-on line.
case "${FORGE:-}" in
  github|gitlab) ;;
  *)
    printf '%s: unsupported or unresolvable forge (remote: %s)\n' "$PROG" "${SLUG:-unknown}" >&2
    printf '  Only github and gitlab remotes are supported.\n' >&2
    printf '  Run: %s/detect-forge.sh %s\n' "$SCRIPT_DIR" "${DET_ARGS[*]:-}" >&2
    exit 2
    ;;
esac

if [[ -n "${AUTH_REASON:-}" ]]; then
  printf '%s: %s is unavailable for %s (%s)\n' "$PROG" "$CLI" "$FORGE" "$AUTH_REASON" >&2
  printf '  Fix: %s auth login\n' "$CLI" >&2
  printf '  Or pass: --token <value>\n' >&2
  exit 2
fi

# --- Who am I? ---------------------------------------------------------------
CURRENT_USER=""
case "$FORGE" in
  github)
    # `gh api user` takes no -R flag; passing one made this call fail and fall
    # through to a second identical call for no reason.
    CURRENT_USER="$(gh api user --jq '.login' 2>/dev/null)"
    ;;
  gitlab)
    CURRENT_USER="${WORKLOG_GITLAB_USER:-}"
    if [[ -z "$CURRENT_USER" ]]; then
      CURRENT_USER="$(glab api user --url "${GITLAB_URL:-https://gitlab.com}" 2>/dev/null \
                      | jq -r '.username // empty')"
    fi
    ;;
esac
if [[ -z "$CURRENT_USER" ]]; then
  printf '%s: could not resolve the current %s username\n' "$PROG" "$FORGE" >&2
  printf '  Run: %s auth login\n' "$CLI" >&2
  exit 2
fi

# --- Who owns the PR? --------------------------------------------------------
AUTHOR=""
COMMIT_AUTHORS=""
case "$FORGE" in
  github)
    PR_DATA="$(gh pr view "$PR_NUMBER" -R "$SLUG" \
                 --json number,isDraft,state,author,commits 2>/dev/null)" || {
      printf '%s: PR #%s not found or inaccessible on %s\n' "$PROG" "$PR_NUMBER" "$SLUG" >&2
      printf '  Check: gh pr view %s -R %s\n' "$PR_NUMBER" "$SLUG" >&2
      exit 2
    }
    [[ -n "$PR_DATA" ]] || {
      printf '%s: PR #%s returned no data on %s\n' "$PROG" "$PR_NUMBER" "$SLUG" >&2
      exit 2
    }
    AUTHOR="$(printf '%s' "$PR_DATA" | jq -r '.author.login // ""')"
    COMMIT_AUTHORS="$(printf '%s' "$PR_DATA" \
      | jq -r '[.commits[]?.authors[]?.login // empty] | unique | .[]' 2>/dev/null)"
    ;;
  gitlab)
    PROJECT_ID="$(glab api "projects/$(printf '%s' "$SLUG" | sed 's|/|%2F|g')" \
                    --url "${GITLAB_URL:-https://gitlab.com}" 2>/dev/null | jq -r '.id // empty')"
    [[ -n "$PROJECT_ID" ]] || {
      printf '%s: could not resolve project id for %s\n' "$PROG" "$SLUG" >&2; exit 2; }
    MR_DATA="$(glab api "projects/$PROJECT_ID/merge_requests/$PR_NUMBER" \
                 --url "${GITLAB_URL:-https://gitlab.com}" 2>/dev/null)"
    [[ -n "$MR_DATA" ]] || {
      printf '%s: MR #%s not found or inaccessible on %s\n' "$PROG" "$PR_NUMBER" "$SLUG" >&2
      exit 2
    }
    AUTHOR="$(printf '%s' "$MR_DATA" | jq -r '.author.username // ""')"
    COMMIT_AUTHORS="$(glab api "projects/$PROJECT_ID/merge_requests/$PR_NUMBER/commits" \
                        --url "${GITLAB_URL:-https://gitlab.com}" 2>/dev/null \
                      | jq -r '.[]?.author_name // empty' | sort -u)"
    ;;
esac

# --- Compare -----------------------------------------------------------------
if [[ -n "$AUTHOR" && "$AUTHOR" == "$CURRENT_USER" ]]; then
  echo "self"
  exit 0
fi

# Commit-author fallback: team repos and drafts iterated by a colleague.
# Read line by line. An unquoted `for x in $COMMIT_AUTHORS` splits on spaces,
# and GitLab's author_name is a display name -- "Fred Tran" became two words,
# neither of which matches any username.
if [[ -n "$COMMIT_AUTHORS" ]]; then
  while IFS= read -r ca; do
    [[ -n "$ca" ]] || continue
    if [[ "$ca" == "$CURRENT_USER" ]]; then
      echo "self"
      exit 0
    fi
  done <<<"$COMMIT_AUTHORS"
fi

if [[ -z "$AUTHOR" ]]; then
  printf '%s: could not determine the author of #%s\n' "$PROG" "$PR_NUMBER" >&2
  exit 2
fi

echo "other"
exit 1
