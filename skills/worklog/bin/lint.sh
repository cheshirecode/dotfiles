#!/usr/bin/env bash
# Validate every task file under people/*/{active,archive}/.
# Thin wrapper around bin/_lint.py.
#
# Usage:
#   bin/lint.sh                 # markdown report, exit 1 on errors
#   bin/lint.sh --file=PATH     # lint one people/*/{active,archive}/*.md file
#   bin/lint.sh --format=json   # machine-readable report
#   bin/lint.sh --cross-task    # include active-task drift checks
#   bin/lint.sh --okf           # require OKF compatibility fields on task files
#   bin/lint.sh --fix-related   # auto-stub undeclared body slug refs
#
# Set WORKLOG_NO_LINT=1 to have callers (e.g. checkpoint.sh) skip this.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
esac

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

exec python3 "$SCRIPT_DIR/_lint.py" "$@"
