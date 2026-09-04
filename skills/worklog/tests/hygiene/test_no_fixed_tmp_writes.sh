#!/usr/bin/env bash
# Test fixtures must not write to fixed /tmp paths. Parallel sessions run
# this suite concurrently (the handover says so), and two runs racing on
# one literal path like /tmp/worklog-lint-missing.out contaminate each
# other silently. Every fixture already owns a mktemp scratch dir; write
# there. Literal /tmp is allowed only as inert data (a fixture URL, an
# expected-output string), never as a real redirect or read target.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"

# A violation is a literal /tmp/<name> that is not built from a variable
# and not a mktemp template. Match reads and writes alike: a fixed read
# path implies a fixed write elsewhere.
violations="$(grep -rnE '/tmp/[A-Za-z0-9._-]+' "$here" \
  --include='*.sh' --include='*.py' \
  | grep -vE 'test_no_fixed_tmp_writes\.sh' \
  | grep -vE '\$|mktemp|XXXXXX|file:///tmp/|artifacts=/tmp/|/tmp/opencode' \
  || true)"

if [ -n "$violations" ]; then
  echo "fixed /tmp paths found in test fixtures (use the test's mktemp scratch dir):" >&2
  printf '%s\n' "$violations" >&2
  exit 1
fi

echo "ok: no fixed /tmp writes in worklog test fixtures"
