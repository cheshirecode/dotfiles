#!/usr/bin/env bash
# Pin `set -o pipefail` across bin/, and demonstrate what its absence costs.
#
# WHY THIS IS A FIXTURE AND NOT A CODE COMMENT
# --------------------------------------------
# bin/log-compact.sh captures the status of a history rewrite like this:
#
#   git rebase -i --root ... 2>&1 | tail -5 || REBASE_STATUS=$?
#
# `$?` there is the PIPELINE's status. With `set -o pipefail` that is git's,
# and a failed rebase is caught. Without it, it is `tail`'s -- always 0 -- and
# a failed rebase reads as a clean one. Nothing else in that script would
# notice: the `||` branch never runs, REBASE_STATUS stays 0, and the script
# proceeds to report success over a broken rewrite. The previous --apply
# implementation dropped 613 commits' file changes in production while passing
# its own verification, so "the rewrite reported success" is exactly the
# signal that must not be forgeable.
#
# The rule "always set pipefail" has been written down before. This asserts it
# instead, and asserts the consequence too -- so deleting line 36 of
# log-compact.sh fails a test that shows the lost status, rather than passing
# a review that reads the same either way.
#
# Exit: 0 all checks pass, 1 a check failed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bin"
FAIL=0
CHECKED=0

note() { printf '  %-6s %s\n' "$1" "$2"; }
fail() { FAIL=1; note FAIL "$1"; }
pass() { note PASS "$1"; }

# Sourced libraries run under the caller's shell options and cannot set their
# own; every entry point that sources them is checked instead. Widening this
# list is a visible diff, which is the point.
is_exempt() {
  case "${1##*/}" in
    _lib.sh|_query.sh) return 0 ;;
    *) return 1 ;;
  esac
}

echo "=== 1. every bash entry point in bin/ sets pipefail ==="
while IFS= read -r script; do
  head -1 "$script" | grep -Eq '^#!.*(bash|sh)\b' || continue
  is_exempt "$script" && continue
  CHECKED=$((CHECKED + 1))
  if grep -Eq '^[[:space:]]*set[[:space:]]+-[a-z]*o?[a-z]*[[:space:]]*.*pipefail' "$script"; then
    :
  else
    fail "${script#"$ROOT"/} does not set pipefail"
  fi
done < <(find "$BIN" -type f -not -path '*__pycache__*' | sort)

# A scan that matched no files would report a clean run. Anchor the count so
# an over-narrow find is a failure and not a green.
if [ "$CHECKED" -lt 20 ]; then
  fail "scanned only $CHECKED scripts; the find pattern stopped matching"
else
  pass "scanned $CHECKED bash entry points"
fi

echo "=== 2. RED: the scan reports a script that omits pipefail ==="
# Proves check 1 can fail. Without this, a broken grep pattern -- one that
# matches nothing and therefore flags nothing -- is indistinguishable from a
# fully compliant bin/.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
printf '#!/usr/bin/env bash\nset -eu\necho hi\n' > "$SCRATCH/no-pipefail.sh"
if grep -Eq '^[[:space:]]*set[[:space:]]+-[a-z]*o?[a-z]*[[:space:]]*.*pipefail' "$SCRATCH/no-pipefail.sh"; then
  fail "the pipefail pattern matched a script that has no pipefail"
else
  pass "pipefail pattern rejects a non-compliant script"
fi
printf '#!/usr/bin/env bash\nset -euo pipefail\necho hi\n' > "$SCRATCH/yes-pipefail.sh"
if grep -Eq '^[[:space:]]*set[[:space:]]+-[a-z]*o?[a-z]*[[:space:]]*.*pipefail' "$SCRATCH/yes-pipefail.sh"; then
  pass "pipefail pattern accepts a compliant script"
else
  fail "the pipefail pattern missed a compliant script"
fi

echo "=== 3. the status-capture idiom really depends on pipefail ==="
# Not a restatement of check 1: this measures the consequence. If a future
# bash made a bare pipeline propagate its producer's status, check 1 would be
# pointless ceremony and this check would say so.
WITH="$(bash -c 'set -euo pipefail; S=0; (exit 42) 2>&1 | tail -5 || S=$?; echo "$S"')"
WITHOUT="$(bash -c 'set -eu; S=0; (exit 42) 2>&1 | tail -5 || S=$?; echo "$S"')"
if [ "$WITH" = "42" ]; then
  pass "with pipefail the producer's status survives the pipe ($WITH)"
else
  fail "expected 42 with pipefail, got '$WITH'"
fi
if [ "$WITHOUT" = "0" ]; then
  pass "without pipefail the producer's failure reads as success ($WITHOUT)"
else
  fail "expected 0 without pipefail, got '$WITHOUT' -- check 1 may be moot now"
fi

echo "=== 4. log-compact.sh still captures the rebase status this way ==="
# The named site the rule exists for. If the idiom is refactored away this
# check must be retargeted deliberately, not silently kept passing.
if grep -q 'REBASE_STATUS=\$?' "$BIN/log-compact.sh"; then
  pass "log-compact.sh captures the rebase status through a pipe"
  if grep -Eq '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail' "$BIN/log-compact.sh"; then
    pass "log-compact.sh sets pipefail, so that capture is the rebase's"
  else
    fail "log-compact.sh captures a piped status WITHOUT pipefail"
  fi
else
  fail "log-compact.sh no longer has REBASE_STATUS=\$? -- retarget this check"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "pipefail discipline: all checks passed"
else
  echo "pipefail discipline: FAILURES above" >&2
fi
exit "$FAIL"
