#!/usr/bin/env bash
# transcript-dump.sh — manual snapshot of the current Claude Code session
# into people/$LDAP/transcripts/<slug>.md. Watermarked + append-mode; does
# NOT modify the task body (archive.sh handles the body-link insertion).
#
# Usage:
#   bin/transcript-dump.sh <slug>          # dump current session for <slug>
#
# Env:
#   CLAUDE_CODE_SESSION_ID                  # required (set by Claude Code)
#   WORKLOG_TRANSCRIPT_JSONL                # optional override (testing)
#   WORKLOG_NO_TRANSCRIPT=1                 # bypass (one-shot disable)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
. "$SCRIPT_DIR/_lib.sh"

SLUG="${1:-}"
if [[ -z "$SLUG" || "$SLUG" == "-h" || "$SLUG" == "--help" ]]; then
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

LDAP="$(resolve_ldap)"

SLUG="$SLUG" LDAP="$LDAP" TRIGGER="manual" \
  python3 "$SCRIPT_DIR/_dump_transcript.py"
