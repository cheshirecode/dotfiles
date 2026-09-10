#!/usr/bin/env bash
# Compatibility entrypoint; pr-review owns the scanner and its token list.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for owner in "$HERE/../../pr-review" \
  "$HOME/.agents/skills/pr-review" "$HOME/.claude/skills/pr-review" \
  "$HOME/.codex/skills/pr-review" "$HOME/.cursor/skills/pr-review"; do
  if [ -f "$owner/bin/leak-scan.sh" ]; then
    exec bash "$owner/bin/leak-scan.sh" "$@"
  fi
done
printf '%s\n' 'leak-scan.sh: install pr-review to use the compatibility scanner' >&2
exit 2
