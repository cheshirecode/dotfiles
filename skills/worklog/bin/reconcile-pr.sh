#!/usr/bin/env bash
# Compare a task's authoritative Worklog-PR linkage with live GitHub state.
# Read-only: emits JSON and never edits the worklog.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1

exec python3 "$SCRIPT_DIR/_reconcile_pr.py" "$REPO_ROOT" "$@"
