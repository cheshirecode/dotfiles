#!/usr/bin/env bash
# Run every worklog test fixture with a scrubbed environment.
#
# Fixtures are globbed, not listed, so a new tests/<area>/<fixture>.sh is
# wired up by existing (CLAUDE.md test discipline: a check nothing runs is
# not coverage). The env scrub exists because fixtures inherit the invoking
# shell: a developer profile exports WORKLOG_* at the real vault (batch and
# status fixtures then graded the wrong checkout) and SLACK_BOT_TOKEN for
# MCP (the scrape-slack "unavailable provider" branch then found a real
# token — and a live-token test run must never reach the real Slack API).
set -uo pipefail
cd "$(dirname "$0")/.."

pass=0
fail=0
skip=0
for fixture in tests/*/*.sh; do
  case "$fixture" in tests/run.sh) continue ;; esac
  # An operational gate marked `runner: requires-data-repo` needs a real
  # worklog data repo. It runs only when the invoker passes SOURCE
  # explicitly — never on inherited WORKLOG_REPO — and is otherwise a
  # visible SKIP, not a silent green and not a permanent red.
  if grep -q '^# runner: requires-data-repo$' "$fixture" && [ -z "${SOURCE:-}" ]; then
    skip=$((skip + 1))
    printf 'SKIP %s (needs a worklog data repo; run with SOURCE=/path/to/repo)\n' "$fixture"
    continue
  fi
  if out=$(env -u WORKLOG_REPO -u WORKLOG_LDAP -u WORKLOG_NS -u WORKLOG_BIN \
    -u SLACK_BOT_TOKEN -u SLACK_TOKEN -u SLACK_TEAM_ID \
    SOURCE="${SOURCE:-}" bash "$fixture" 2>&1); then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$fixture"
    printf '%s\n' "$out" | tail -5
  fi
done

printf 'worklog tests: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
