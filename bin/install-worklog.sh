#!/usr/bin/env bash
# Set up a worklog vault for this machine and login, via the skill's
# bootstrap.sh. Idempotent.
#
#   WORKLOG_REMOTE   vault to join: a git URL, or owner/repo for GitHub.
#                    Unset = report the vaults already here and stop.
#   WORKLOG_TARGET   clone path (default: bootstrap.sh probe's SUGGESTED_REPO)
#   WORKLOG_NS       namespace under people/ (default: from the git identity)
#
# No default remote. The old default cloned one fixed vault into
# ~/Documents/projects/_worklog, which on a machine with a work vault at that
# path is the other vault. It also called <vault>/bin/install-hooks.sh, which
# the data repo does not ship, so hooks were never wired.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$REPO_ROOT/skills/worklog/bin/bootstrap.sh"
[[ -x "$BOOT" ]] || { echo "install-worklog: missing $BOOT" >&2; exit 1; }

probe="$("$BOOT" probe)"
vaults="$(sed -n 's/^VAULTS=//p' <<<"$probe")"

remote="${WORKLOG_REMOTE:-}"
if [[ -z "$remote" ]]; then
  echo "install-worklog: WORKLOG_REMOTE unset — no vault cloned."
  if [[ "${vaults:-0}" -gt 0 ]]; then
    echo "install-worklog: vaults already here (path, origin, namespace, author):"
    grep $'^vault\t' <<<"$probe" | cut -f2- | sed 's/^/  /'
    echo "install-worklog: record this instance in each: $BOOT apply --repo <path> --ns <ns>"
  else
    echo "install-worklog: next: WORKLOG_REMOTE=<url> bin/install-worklog.sh, or /worklog init"
  fi
  exit 0
fi

# owner/repo short form -> GitHub HTTPS URL. Anything with a scheme, a colon
# (scp-style SSH) or a leading / or . is already a location git understands.
case "$remote" in
  *://*|*:*|/*|.*) ;;
  */*) remote="https://github.com/$remote.git" ;;
  *) echo "install-worklog: WORKLOG_REMOTE='$remote' is neither a git URL nor owner/repo" >&2; exit 2 ;;
esac

target="${WORKLOG_TARGET:-$(sed -n 's/^SUGGESTED_REPO=//p' <<<"$probe")}"
args=(apply --repo "$target" --remote "$remote")
[[ -n "${WORKLOG_NS:-}" ]] && args+=(--ns "$WORKLOG_NS")
"$BOOT" "${args[@]}"
echo "install-worklog: next: /worklog init  (inside Claude Code)"
