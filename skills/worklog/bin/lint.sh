#!/usr/bin/env bash
# Validate every task file under people/*/{active,archive}/.
# Thin wrapper around bin/_lint.py.
#
# Usage:
#   bin/lint.sh                 # markdown report, exit 1 on errors
#   bin/lint.sh --format=json   # machine-readable report
#
# Set WORKLOG_NO_LINT=1 to have callers (e.g. checkpoint.sh) skip this.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

exec python3 "$SCRIPT_DIR/_lint.py" "$@"
