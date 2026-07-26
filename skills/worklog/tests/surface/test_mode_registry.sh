#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKLOG_BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo/people/tester/active" "$TMP/repo/people/tester/archive"
cp "$ROOT/templates/README.md" "$TMP/repo/README.md"
cp "$ROOT/templates/AGENTS.md" "$TMP/repo/AGENTS.md"
git -C "$TMP/repo" init -q

WORKLOG_REPO="$TMP/repo" \
WORKLOG_LDAP=tester \
CODEX_SKILL_PATH="$ROOT/SKILL.md" \
MODE_REGISTRY_PATH="$ROOT/modes/registry.md" \
MODE_INIT_PATH="$ROOT/modes/init.md" \
  "$WORKLOG_BIN/codex-surface-check.sh" >/dev/null

awk '
  /MODE_REGISTRY_END/ { print "- fixture-mode" }
  { print }
' "$ROOT/modes/registry.md" > "$TMP/registry.md"

if WORKLOG_REPO="$TMP/repo" \
  WORKLOG_LDAP=tester \
  CODEX_SKILL_PATH="$ROOT/SKILL.md" \
  MODE_REGISTRY_PATH="$TMP/registry.md" \
  MODE_INIT_PATH="$ROOT/modes/init.md" \
    "$WORKLOG_BIN/codex-surface-check.sh" >/dev/null 2>&1; then
  echo "FAIL: checker ignored a registry-only mode"
  exit 1
fi

echo "ok: command surfaces follow the packaged mode registry"
