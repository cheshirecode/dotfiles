#!/usr/bin/env bash
# `command -v a b c` is not a check that all three exist.
#
# It prints only the tools it finds and exits 0 if ANY ONE of them exists. A
# preflight written that way can only fail when EVERY tool is missing, which
# is the one case that needs no check. bin/e2e.sh had exactly this, under a
# step named "bash + python3 + perl + git + ripgrep + jq present" -- and it
# passed on a box with no ripgrep binary (verified 2026-09-03).
#
# The same idiom was documented in serena-rg-search's SKILL.md as the way to
# check tool availability. Both are now loops that name what is absent.
#
# Exit: 0 all checks pass, 1 a check failed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bin"
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

echo "=== 1. the idiom really does fail open ==="
# Measured, not asserted from memory. If a future bash made multi-arg
# `command -v` require all arguments, checks 2-3 would be pointless and this
# case says so rather than leaving them as unexplained ceremony.
if bash -c 'command -v sh definitely-not-a-real-binary-xyz >/dev/null 2>&1'; then
  pass "multi-arg command -v exits 0 with one argument missing"
else
  fail "multi-arg command -v now requires all arguments -- checks below are moot"
fi
if bash -c 'command -v definitely-not-a-real-binary-xyz >/dev/null 2>&1'; then
  fail "command -v returned 0 for a binary that does not exist"
else
  pass "single-arg command -v correctly reports an absent binary"
fi

echo "=== 2. no executable line in bin/ uses the multi-arg form ==="
# Comments explaining the trap are fine and expected; executable uses are not.
SCANNED=0
HITS=""
while IFS= read -r script; do
  head -1 "$script" | grep -Eq '^#!.*(bash|sh)\b' || continue
  SCANNED=$((SCANNED + 1))
  while IFS= read -r line; do
    stripped="${line#"${line%%[![:space:]]*}"}"
    case "$stripped" in \#*) continue ;; esac
    printf '%s' "$stripped" | grep -Eq 'command -v +[A-Za-z0-9_.-]+ +[A-Za-z0-9_.-]+' \
      && HITS="$HITS\n    ${script#"$ROOT"/}: $stripped"
  done < "$script"
done < <(find "$BIN" -type f -not -path '*__pycache__*' | sort)

if [ "$SCANNED" -lt 20 ]; then
  fail "scanned only $SCANNED scripts; the find pattern stopped matching"
elif [ -n "$HITS" ]; then
  fail "multi-arg command -v in executable code:$(printf '%b' "$HITS")"
else
  pass "no executable multi-arg command -v in $SCANNED scripts"
fi

echo "=== 3. RED: the scan can actually see such a line ==="
# Without this, a broken pattern -- one matching nothing -- is
# indistinguishable from a clean bin/.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
printf '#!/usr/bin/env bash\ncommand -v foo bar baz >/dev/null\n' > "$SCRATCH/bad.sh"
if grep -Eq 'command -v +[A-Za-z0-9_.-]+ +[A-Za-z0-9_.-]+' "$SCRATCH/bad.sh"; then
  pass "the pattern matches a known-bad line"
else
  fail "the pattern missed a known-bad line"
fi
printf '#!/usr/bin/env bash\ncommand -v foo >/dev/null\n' > "$SCRATCH/good.sh"
if grep -Eq 'command -v +[A-Za-z0-9_.-]+ +[A-Za-z0-9_.-]+' "$SCRATCH/good.sh"; then
  fail "the pattern flagged a correct single-arg use"
else
  pass "the pattern accepts a correct single-arg use"
fi

echo "=== 4. e2e.sh's preflight names the tool that is missing ==="
# The behaviour the fix exists for: not merely "it fails", but that it says
# WHICH tool, so the reader is not left bisecting six of them.
PREFLIGHT="$(sed -n '/preflight: bash/,/^$/p' "$BIN/e2e.sh")"
if printf '%s' "$PREFLIGHT" | grep -q 'for t in'; then
  pass "the preflight loops over the tools"
else
  fail "the preflight is not a loop"
fi
if printf '%s' "$PREFLIGHT" | grep -q 'missing required tools'; then
  pass "the preflight reports the missing tool by name"
else
  fail "the preflight does not name what is missing"
fi

echo
[ "$FAIL" -eq 0 ] && echo "tool presence: all checks passed" || echo "tool presence: FAILURES above" >&2
exit "$FAIL"
