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

CODEX_SKILL_PATH="${CODEX_SKILL_PATH:-$HOME/.codex/skills/worklog/SKILL.md}"
MODE_INIT_PATH="${MODE_INIT_PATH:-$SCRIPT_DIR/../modes/init.md}"
MODE_REGISTRY_PATH="${MODE_REGISTRY_PATH:-$SCRIPT_DIR/../modes/registry.md}"

case "${1:-}" in
  -h|--help)
    cat <<'EOF'
usage: bin/codex-surface-check.sh

Checks that README.md, AGENTS.md, and the local Codex worklog skill advertise
the same worklog command names.

Environment:
  CODEX_SKILL_PATH=/path/to/SKILL.md   override local Codex skill path
  MODE_REGISTRY_PATH=/path/to/registry.md
                                       override public mode registry
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

if [[ ! -f "$MODE_REGISTRY_PATH" ]]; then
  echo "codex-surface-check: mode registry not found at $MODE_REGISTRY_PATH" >&2
  exit 1
fi

EXPECTED=()
while IFS= read -r cmd; do
  [[ -n "$cmd" ]] && EXPECTED+=("$cmd")
done < <(
  sed -n '/MODE_REGISTRY_BEGIN/,/MODE_REGISTRY_END/ {
    s/^- \([a-z0-9-][a-z0-9-]*\)$/\1/p
  }' "$MODE_REGISTRY_PATH"
)
if [[ ${#EXPECTED[@]} -eq 0 ]]; then
  echo "codex-surface-check: mode registry is empty or malformed" >&2
  exit 1
fi

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
    if grep -Eq "(^|[^A-Za-z0-9_/])/?worklog[[:space:]]+${cmd}([^A-Za-z0-9_-]|$)|^[[:space:]]+${cmd}([[:space:]<\\[]|$)" "$surface"; then
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

if [[ -f "$CODEX_SKILL_PATH" ]]; then
  if grep -Fq "Non-Claude agents don't invoke this skill" "$CODEX_SKILL_PATH"; then
    echo "codex-surface-check: Codex skill still excludes its own invocation" >&2
    exit 1
  fi
  if ! grep -Fq "Codex agents may invoke this skill directly" "$CODEX_SKILL_PATH"; then
    echo "codex-surface-check: Codex skill missing explicit invocation contract" >&2
    exit 1
  fi
fi

if [[ ! -f "$MODE_INIT_PATH" ]]; then
  echo "codex-surface-check: init mode not found at $MODE_INIT_PATH" >&2
  exit 1
fi
if ! grep -Fq "OpenAI Codex CLI" "$MODE_INIT_PATH" || ! grep -Fq "update_plan" "$MODE_INIT_PATH"; then
  echo "codex-surface-check: init mode missing Codex update_plan hydration contract" >&2
  exit 1
fi

echo "codex-surface-check: ok"
