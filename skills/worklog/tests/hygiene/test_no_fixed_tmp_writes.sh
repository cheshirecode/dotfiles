#!/usr/bin/env bash
# Test fixtures must not write to fixed /tmp paths. Parallel sessions run
# this suite concurrently (the handover says so), and two runs racing on
# one literal path like /tmp/worklog-lint-missing.out contaminate each
# other silently. Every fixture already owns a mktemp scratch dir; write
# there. Literal /tmp is allowed only as inert data (a fixture URL, an
# expected-output string), never as a real redirect or read target.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"

# A violation is any literal /tmp/<name> occurrence. Match reads and
# writes alike: a fixed read path implies a fixed write elsewhere.
# Whitelist specific inert tokens, never whole lines: a line-level filter
# (the first version excluded any line containing "$") goes blind exactly
# where violations are most common — a redirect next to a variable, like
# `"$BIN/x.sh" >/tmp/out`. Proven missed before this token-level rewrite.
violations="$(grep -rnE '/tmp/[A-Za-z0-9._-]+' "$here" \
  --include='*.sh' --include='*.py' \
  | grep -vE 'test_no_fixed_tmp_writes\.sh' \
  | grep -vE 'file:///tmp/|artifacts=/tmp/' \
  || true)"

if [ -n "$violations" ]; then
  echo "fixed /tmp paths found in test fixtures (use the test's mktemp scratch dir):" >&2
  printf '%s\n' "$violations" >&2
  exit 1
fi

echo "ok: no fixed /tmp writes in worklog test fixtures"
