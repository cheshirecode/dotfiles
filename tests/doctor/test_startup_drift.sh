#!/usr/bin/env bash
# doctor's three restart-recurring checks: a tool that resolves to a shell
# function is not an installed tool; a missing node_modules makes a suite lane
# SKIP rather than fail; a modified tracked file is drift worth naming.
#
# Each of these was a silent failure on this workspace before doctor covered
# it: the tool probe printed "OK rg rg" with no binary present, the skip read
# as green while 38 checks went unrun, and the platform's .bashrc injection was
# invisible until someone ran git status by hand.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/doctor-drift.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# A copy, not a clone: the behaviour under test lives in the working tree, and
# `git clone` would take HEAD instead. Reverting the copy would do the same.
cp -r "$REPO" "$TMP/d"
D="$TMP/d"

run_doctor() { ( cd "$D" && timeout 180 bash bin/doctor.sh 2>&1 ); }

# 1. A shell function is not an executable. Exported so doctor's own bash sees
#    it. PATH is deliberately left alone: a function takes precedence in command
#    lookup, so this reproduces the real case (binary present or not) without
#    breaking doctor's ability to run at all.
out="$(rg() { :; }; export -f rg; run_doctor)" || true
if ! printf '%s' "$out" | grep -q 'shell function or alias'; then
  note "a tool resolving to a shell function was not reported as unusable"
fi
if printf '%s' "$out" | grep -qE '^  OK +rg rg$'; then
  note "doctor still prints the bare-word OK that hid a missing binary"
fi

# 2. node_modules absent -> WARN naming the skip, not silence.
rm -rf "$D"/packages/*/node_modules
out="$(run_doctor)"
if ! printf '%s' "$out" | grep -q 'node_modules missing'; then
  note "a missing node_modules was not reported"
fi
if ! printf '%s' "$out" | grep -q 'skips instead of running'; then
  note "the report did not say the lane skips rather than fails"
fi

# 3. A dirtied shell dotfile gets the machine-local guidance; anything else
#    gets a plain uncommitted-work report rather than advice that does not fit.
printf '\n# injected\n' >> "$D/.bashrc"
printf '\n# edit\n' >> "$D/README.md"
out="$(run_doctor)"
printf '%s' "$out" | grep -q '\.bashrc modified — machine-local shell config' \
  || note "a dirtied shell dotfile did not get the machine-local guidance"
printf '%s' "$out" | grep -q 'README.md modified — uncommitted work' \
  || note "an ordinary modified file did not get the plain report"
printf '%s' "$out" | grep -q 'README.md modified — machine-local' \
  && note "an ordinary modified file was told to move to ~/.shell_common.local"

[ "$fails" -eq 0 ] || exit 1
echo "ok: doctor reports function-shaped tools, missing node_modules, and tracked-file drift"
