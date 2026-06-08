#!/usr/bin/env bash
# Push unpushed autosave commits left behind by push debounce.
# Safe no-op when origin is current. Called from SessionEnd hooks and after
# checkpoint/archive so debounced local autosaves still reach origin.
#
# Usage: bin/autosave-flush.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

upstream="$(git rev-parse --abbrev-ref @{u} 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  exit 0
fi

if ! git rev-list "${upstream}..HEAD" 2>/dev/null | grep -q .; then
  rm -f .cache/autosave-push-pending
  exit 0
fi

if push_with_retry; then
  rm -f .cache/autosave-push-pending
  echo "autosave-flush: pushed pending commits"
fi
