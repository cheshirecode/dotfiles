#!/usr/bin/env bash
# export-setup.sh must find the vault's Claude memory dir from the vault path.
# It once built `-Users-<ldap>-Documents-projects--worklog`, which matched one
# macOS layout; any other path or namespace read as "no memory files".
set -uo pipefail
unset BASH_ENV
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [[ "$2" == 0 ]]; then echo "ok: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }

vault="$TMP/src/some_place/_worklog"
mkdir -p "$TMP/home" "$vault/people"
git -C "$vault" init -q
slug="$(printf '%s' "$(cd "$vault" && pwd -P)" | sed 's|[^A-Za-z0-9]|-|g')"
mem="$TMP/home/.claude/projects/$slug/memory"
run() { env -i HOME="$TMP/home" PATH="$PATH" WORKLOG_REPO="$(cd "$vault" && pwd -P)" WORKLOG_LDAP=oss \
  bash "$ROOT/bin/export-setup.sh" --dry-run 2>/dev/null; }

out="$(run)"
grep -q "memory: $mem (absent)" <<<"$out"; check "missing memory dir reads as absent" $?
mkdir -p "$mem"; echo x > "$mem/a.md"; echo y > "$mem/b.md"
out="$(run)"
grep -q "memory: $mem (2 files)" <<<"$out"; check "memory dir derived from the vault path (namespace oss)" $?
(( fails == 0 ))
