#!/usr/bin/env bash
# Corpora for the internal-ref leak scan.
#
# The pattern lived twice in SKILL.md step 7b -- once for the PR body, once for
# the diff -- and was checked by nobody. Running it against a corpus found
# three classes of leak it could not express:
#
#   people/<ldap>/archive/<slug>.md   only /active was matched, and every task
#                                     ends up in archive/
#   /tightening-a-pr                  only /ship-hygiene and /worklog were
#                                     named, though a sibling skill whose whole
#                                     job is writing PR text is the likeliest
#                                     command name to appear in one
#   worklog/<ldap>/<slug>             the worklog_id frontmatter form, which
#                                     has no leading slash
#
# A leak scan that cannot express a leak reports the PR clean, which is the
# same output as a clean PR.
#
# Exit: 0 all cases pass, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/bin/leak-scan.sh"
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

scan() { printf '%s\n' "$1" | "$SCAN" --label test >/dev/null 2>&1; }

echo "=== 1. every known leak form is caught ==="
LEAKS=(
  'Worklog: skills-script-mechanical-ops'
  '[POST-MERGE-CLEANUP] drop the branch'
  'next_action: keep going'
  'see people/fred.tran/active/my-task.md'
  'see people/fred.tran/archive/my-task.md'
  'tracked in worklog/fred.tran/some-slug'
  'Tracked in worklog mini-app-preview-gallery-image-memory.'
  'see worklog responsive-image-pipeline-design for the decision'
  'Tracked in worklog builder-preview.'
  'Iteration 3 of the refactor'
  'run /ship-hygiene after'
  'ran /tightening-a-pr on this'
  'per the audit, we split this'
  'per the critique, narrowed'
  'scope chosen: minimal'
)
caught=0
for leak in "${LEAKS[@]}"; do
  if scan "$leak"; then
    fail "not caught: $leak"
  else
    caught=$((caught + 1))
  fi
done
[ "$caught" -eq "${#LEAKS[@]}" ] && pass "all ${#LEAKS[@]} leak forms caught"

echo "=== 2. legitimate product text is not flagged ==="
# The control. A scanner that flags everything catches every leak in case 1
# and is useless -- and worse than useless, because people stop reading it.
CLEAN=(
  'Adds retry logic to the payment worker'
  'Fixes a race in the archive uploader'
  'This is the second iteration we shipped'
  'Refactors the worklog export module'
  'Moves people into the new org chart view'
  'See https://example.com/api-reference for the schema'
)
clean_ok=0
for line in "${CLEAN[@]}"; do
  if scan "$line"; then
    clean_ok=$((clean_ok + 1))
  else
    fail "false positive on: $line"
  fi
done
[ "$clean_ok" -eq "${#CLEAN[@]}" ] && pass "all ${#CLEAN[@]} clean lines pass"

echo "=== 3. empty input is refused, not reported clean ==="
# A failed `gh pr view` emits nothing. Without this the scan's happiest output
# is produced by its most broken input.
set +e
printf '' | "$SCAN" --label body >/dev/null 2>&1; rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "empty stdin exits 2"
else
  fail "empty stdin exited $rc; expected 2"
fi
set +e
printf '   \n\n  \n' | "$SCAN" --label body >/dev/null 2>&1; rc=$?
set -e
if [ "$rc" -eq 2 ]; then
  pass "whitespace-only stdin exits 2"
else
  fail "whitespace-only stdin exited $rc; expected 2"
fi

echo "=== 4. exit codes separate the verdict from the error ==="
set +e
printf 'all good here\n' | "$SCAN" --label body >/dev/null 2>&1; clean_rc=$?
printf 'next_action: x\n' | "$SCAN" --label body >/dev/null 2>&1; leak_rc=$?
"$SCAN" --nonsense </dev/null >/dev/null 2>&1; usage_rc=$?
set -e
[ "$clean_rc" -eq 0 ] && pass "clean exits 0" || fail "clean exited $clean_rc"
[ "$leak_rc"  -eq 1 ] && pass "leak found exits 1" || fail "leak exited $leak_rc"
[ "$usage_rc" -eq 2 ] && pass "usage error exits 2" || fail "usage exited $usage_rc"

echo "=== 5. every sibling skill name is a scannable command ==="
# Placement: adding a skill without extending SKILL_COMMANDS is caught when the
# skill is added, not the next time its name ships inside a PR description.
SKILLS_DIR="$(cd "$ROOT/.." && pwd)"
missing=""
found=0
for d in "$SKILLS_DIR"/*/; do
  name="$(basename "$d")"
  [ -f "$d/SKILL.md" ] || continue
  found=$((found + 1))
  if scan "mentioned /$name in the body"; then
    missing="$missing $name"
  fi
done
if [ "$found" -lt 5 ]; then
  fail "only $found sibling skills found; the directory scan stopped matching"
elif [ -n "$missing" ]; then
  fail "skill names absent from the leak pattern:$missing"
else
  pass "all $found sibling skill names are covered"
fi

echo "=== 6. --print-pattern emits a usable regex ==="
PAT="$("$SCAN" --print-pattern)"
if [ -n "$PAT" ] && printf 'next_action: x\n' | grep -qiE "$PAT"; then
  pass "--print-pattern round-trips through grep"
else
  fail "--print-pattern produced an unusable regex: $PAT"
fi

echo "=== 7. a large single-line input is scanned, and not copied in the shell ==="
# A generated bundle or lock file puts megabytes on one diff line. The scan
# used to slurp stdin into a variable, strip whitespace into a second copy,
# then stream the variable through a pipe twice more. Measured on an 8MB single
# line: 1007ms, against 123ms for grep alone on the same pattern.
#
# The guard is structural, not a stopwatch. A wall-clock bound measures
# whatever else the machine is doing, but "does the whole input become a shell
# string" is a property of the script and answers the same question.
if grep -qE 'INPUT="\$\(cat\)"|\$\{INPUT//' "$SCAN"; then
  fail "the scan builds a shell copy of the whole input; stage stdin in a file"
else
  pass "stdin is not slurped into a shell variable"
fi

# And the behaviour that matters is unchanged at that size: a leak on a very
# long line is still found, and a clean one still counted.
big_leak="$(mktemp)"; big_clean="$(mktemp)"
trap 'rm -f "$big_leak" "$big_clean"' EXIT
awk 'BEGIN { s="ab-"; for (i = 0; i < 18; i++) s = s s; print "worklog " s }' > "$big_leak"
awk 'BEGIN { s="x";   for (i = 0; i < 18; i++) s = s s; print s }'            > "$big_clean"
set +e
"$SCAN" --label big </"$big_leak" >/dev/null 2>&1; big_leak_rc=$?
big_clean_out="$("$SCAN" --label big <"$big_clean" 2>&1)"; big_clean_rc=$?
set -e
[ "$big_leak_rc" -eq 1 ] \
  && pass "a leak on a multi-megabyte line still exits 1" \
  || fail "multi-megabyte leak line exited $big_leak_rc; expected 1"
[ "$big_clean_rc" -eq 0 ] && [ "${big_clean_out##*(}" = "1 lines scanned)" ] \
  && pass "a clean multi-megabyte line counts as one line" \
  || fail "clean multi-megabyte line: rc=$big_clean_rc out='$big_clean_out'"

# The reported total must count a final line that has no trailing newline.
# `wc -l < file` counts newlines, so it reports one fewer and the count drifts
# for exactly the inputs a pipe from `gh` produces. The old form got this right
# by accident: command substitution stripped the trailing newline and printf
# put exactly one back.
set +e
nonl_out="$(printf 'alpha\nbeta' | "$SCAN" --label nonl 2>&1)"; nonl_rc=$?
set -e
[ "$nonl_rc" -eq 0 ] && [ "${nonl_out##*(}" = "2 lines scanned)" ] \
  && pass "a final line with no newline is counted" \
  || fail "unterminated last line: rc=$nonl_rc out='$nonl_out'"

echo
[ "$FAIL" -eq 0 ] && echo "leak-scan: all cases passed" || echo "leak-scan: FAILURES above" >&2
exit "$FAIL"
