#!/usr/bin/env bash
# The impeccable doctor check must tell its four answers apart:
#
#   on demand   skill linked, plugin not enabled      -> OK
#   enabled     plugin enabled (hooks on every edit)  -> FAIL
#   absent      no skill, plugin not enabled          -> ABSENT
#   unreadable  settings.json not JSON                -> UNKNOWN
#
# The enabled case is the one that matters: its hooks run a downloaded engine
# at every session start and after every edit, and nothing else reports it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${DOCTOR_BIN:-$ROOT/bin/doctor.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

mk() {  # mk <name> <settings-json> <with-skill:0|1> -> prints the claude home
  local ch="$T/$1/.claude"; mkdir -p "$ch"; printf '%s' "$2" > "$ch/settings.json"
  if [ "$3" = 1 ]; then mkdir -p "$ch/skills/impeccable"; echo "name: impeccable" > "$ch/skills/impeccable/SKILL.md"; fi
  echo "$ch"
}
expect() {  # expect <label> <claude-home> <ERE>
  local out; out="$(DOCTOR_CLAUDE_HOME="$2" bash "$DOCTOR" 2>&1 | sed -n '/doctor: impeccable on demand/,/^doctor: [0-9]/p')"
  if printf '%s' "$out" | grep -Eq "$3"; then ok "$1"; else bad "$1: $(printf '%s' "$out" | sed -n 2p)"; fi
}

expect "linked skill with the plugin disabled reports OK" \
  "$(mk ok '{"enabledPlugins":{"impeccable@impeccable":false}}' 1)" 'OK +impeccable available on demand'
expect "an enabled plugin reports FAIL even with the skill linked" \
  "$(mk on '{"enabledPlugins":{"impeccable@impeccable":true}}' 1)" 'FAIL +impeccable plugin ENABLED'
expect "no skill and no plugin reports ABSENT" \
  "$(mk none '{}' 0)" 'ABSENT +impeccable not set up'
expect "unreadable settings report UNKNOWN, not OK" \
  "$(mk broken '{"x": ' 1)" 'UNKNOWN +impeccable state unreadable'

# Inert-lane guard: four cases, each must have asserted.
[ $((pass + fail)) -eq 4 ] || bad "ran $((pass + fail)) cases, want 4"
printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
