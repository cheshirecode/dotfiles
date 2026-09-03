#!/usr/bin/env bash
# The header comment is what a reader reaches for first, so it must agree with
# --help. It drifted: lines 8-9 showed two --reason examples ("shipped" and
# "superseded by eng-1600-foo") and never mentioned --summary at all, while
# --help named the full six-value enum and documented --summary. A peer session
# read `sed -n '2,12p'` and filed a false "docs gap" report about --help
# without ever running it.
#
# Assert the drift-prone facts, not the prose: every flag --help documents must
# appear in the header, and every enum value --help lists must appear too.
set -euo pipefail

BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
ARCHIVE="$BIN/archive.sh"

# The leading comment block: from line 2 to the first non-comment line.
header="$(awk 'NR==1 {next} /^#/ {print; next} {exit}' "$ARCHIVE")"
help="$("$ARCHIVE" --help)"

[[ -n "$header" ]] || { echo "FAIL: no header comment block"; exit 1; }
[[ -n "$help" ]]   || { echo "FAIL: --help printed nothing"; exit 1; }

fail=0

for flag in --pr --reason --summary; do
  grep -q -- "$flag" <<< "$help" || { echo "FAIL: --help lost $flag"; fail=1; continue; }
  if ! grep -q -- "$flag" <<< "$header"; then
    echo "FAIL: --help documents $flag but the header comment never mentions it"
    fail=1
  fi
done

for value in shipped declined abandoned superseded merged obsolete; do
  grep -q "\b$value\b" <<< "$help" || continue
  if ! grep -q "\b$value\b" <<< "$header"; then
    echo "FAIL: --reason enum value '$value' is in --help but missing from the header comment"
    fail=1
  fi
done

# The header must not present a partial enum as if it were the whole story.
if grep -q 'superseded by eng-1600-foo' <<< "$header"; then
  echo "FAIL: header still shows the two-example --reason form instead of the enum"
  fail=1
fi

if (( fail )); then
  echo "--- header ---"; printf '%s\n' "$header"
  echo "--- --help ---"; printf '%s\n' "$help"
  exit 1
fi

echo "ok: archive.sh header comment names the same flags and --reason enum as --help"
