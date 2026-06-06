#!/usr/bin/env bash
# Check that Codex-facing worklog command surfaces advertise the same command
# names. This catches README/AGENTS/local Codex skill menu drift only; behavior
# still belongs to AGENTS.md and the helper scripts.
#
# Usage:
#   bin/codex-surface-check.sh
#   CODEX_SKILL_PATH=/path/to/SKILL.md bin/codex-surface-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
cd "$REPO_ROOT"

EXPECTED=(help init sync status context spawn export import lint review)
CODEX_SKILL_PATH="${CODEX_SKILL_PATH:-$HOME/.codex/skills/worklog/SKILL.md}"

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
usage: bin/codex-surface-check.sh

Checks that README.md, AGENTS.md, and the local Codex worklog skill advertise
the same worklog command names.

Environment:
  CODEX_SKILL_PATH=/path/to/SKILL.md   override local Codex skill path
EOF
    exit 0
    ;;
  "")
    ;;
  *)
    echo "unknown arg: $1" >&2
    exit 2
    ;;
esac

SURFACES=("README.md" "AGENTS.md")
if [[ -f "$CODEX_SKILL_PATH" ]]; then
  SURFACES+=("$CODEX_SKILL_PATH")
else
  echo "codex-surface-check: warning: Codex skill not found at $CODEX_SKILL_PATH" >&2
fi

missing=0
for surface in "${SURFACES[@]}"; do
  echo "== $surface =="
  for cmd in "${EXPECTED[@]}"; do
    if grep -Eq "(^|[^A-Za-z0-9_/])/?worklog ${cmd}([^A-Za-z0-9_-]|$)" "$surface"; then
      printf '  ok      %s\n' "$cmd"
    else
      printf '  missing %s\n' "$cmd"
      missing=1
    fi
  done
done

if (( missing )); then
  echo "codex-surface-check: command surface drift detected" >&2
  exit 1
fi

echo "codex-surface-check: ok"
