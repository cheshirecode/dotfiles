#!/usr/bin/env bash
# boundary-lint.sh - scan a worklog clone for terms that belong to another clone/domain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  bin/boundary-lint.sh [--config=PATH] [--include=GLOB] [--exclude=GLOB] [--deny-re=REGEX] [--format=text|json]

Read-only guardrail for split worklog clones. By default it scans the active,
archive, and generated project markdown in $WORKLOG_REPO (or the current
worklog repo) using .worklog-boundary.json:

  {
    "schema": "worklog.boundary.v1",
    "label": "oss tracker",
    "deny": [{"pattern": "ideogram-ai|sales-eng", "note": "work tracker only"}]
  }

The profile may also set include/exclude glob lists, allow exceptions of
{path, pattern}, and ignore_case (default true). Exit 1 means at least one
boundary violation was found.
EOF
  exit 0
fi

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1

exec python3 "$SCRIPT_DIR/_boundary_lint.py" --repo "$REPO_ROOT" "$@"
