#!/usr/bin/env bash
# macOS ships /bin/bash 3.2, which has no mapfile/readarray: the probe died
# on "mapfile: command not found" (rc 127) before reading anything, and in a
# shell without set -e the same call leaves the array silently empty
# (fixed in 2bdaaac, which shipped without a test). The suite
# runs under `env bash` — Homebrew bash 5 on the machines that develop this
# repo — so nothing here would catch the builtin coming back. Two guards:
#   1. static: no bash-4-only builtin appears in skills/worklog/bin/*.sh
#      (portable; works even where /bin/bash is bash 5)
#   2. functional: related-search.sh produces real output under /bin/bash
#      (on macOS that is bash 3.2, the interpreter that actually broke)
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/bin/related-search.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

unset WORKLOG_LDAP || true

echo "=== 1. no bash-4-only builtins in bin/*.sh ==="
# mapfile/readarray and `declare -A` do not exist in bash 3.2. Without set -e
# the failed mapfile leaves an empty array and the script keeps going on data
# it never read. Keep them out rather than trusting review to spot them.
set +e
HITS="$(grep -nE '\bmapfile\b|\breadarray\b|declare -A' "$ROOT"/bin/*.sh 2>/dev/null)"
set -e
if [ -z "$HITS" ]; then
  pass "bin/*.sh is free of mapfile/readarray/declare -A"
else
  fail "bash-4-only builtins found: $(tr '\n' '/' <<<"$HITS")"
fi

echo "=== 2. related-search.sh works under /bin/bash ==="
REPO="$TMP/repo"
mkdir -p "$REPO/people/tester/active" "$REPO/people/tester/archive"
cat > "$REPO/people/tester/active/t.md" <<'EOF'
---
slug: t
project: alpha
---

mentions widget here
EOF
(cd "$REPO" && git init -q .)
export WORKLOG_REPO="$REPO"
if [ -x /bin/bash ]; then
  set +e
  OUT="$(/bin/bash "$SCRIPT" --projects 2>&1)"; RC=$?
  set -e
  if [ "$RC" -eq 0 ] && [ "$OUT" = "alpha" ]; then
    pass "--projects under /bin/bash ($(/bin/bash -c 'echo $BASH_VERSION'))"
  else
    fail "--projects under /bin/bash gave rc=$RC output: $(tr '\n' '/' <<<"$OUT")"
  fi
  set +e
  OUT="$(/bin/bash "$SCRIPT" widget 2>&1)"; RC=$?
  set -e
  if [ "$RC" -eq 0 ] && grep -q 't.md' <<<"$OUT"; then
    pass "keyword search under /bin/bash finds the file"
  else
    fail "keyword search under /bin/bash gave rc=$RC output: $(tr '\n' '/' <<<"$OUT")"
  fi
else
  pass "no /bin/bash on this machine; static guard above still applies"
fi

echo
[ "$FAIL" -eq 0 ] && echo "bash32-portability: all cases passed" || echo "bash32-portability: FAILURES above" >&2
exit "$FAIL"
