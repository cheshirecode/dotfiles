#!/usr/bin/env bash
# The dotfiles push-gate check must tell its answers apart.
#
# bin/git-hooks/pre-push was not wired in a Coder clone (2026-10-08) and
# nothing said so, so a push to the public remote would have gone unscanned.
#
#   armed         public remote, gate linked             -> OK
#   unwired       public remote, no pre-push             -> FAIL
#   foreign       public remote, unrelated pre-push      -> FAIL (a file is not the gate)
#   private only  every remote marked private            -> OK (nothing to gate)
#   no checkout   not a git repo                         -> ABSENT
#
# Each case is a scratch repo, so the failure paths are reachable.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${DOCTOR_BIN:-$ROOT/bin/doctor.sh}"

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

if [ ! -x "$DOCTOR" ]; then
  echo "test_push_gate_states NOT RUN — nothing asserted; $DOCTOR missing or not executable." >&2
  exit 2
fi

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"

# $2 = armed | unwired | foreign | private
make_repo() {
  local d="$T/$1" mode="$2"
  git init -q "$d"
  git -C "$d" remote add origin "$T/origin.git"
  git -C "$d" config remote.origin.dotfiles-private true
  [ "$mode" = private ] || git -C "$d" remote add pub "$T/pub.git"
  case "$mode" in
    armed)   ln -s "$ROOT/bin/git-hooks/pre-push" "$d/.git/hooks/pre-push" ;;
    foreign) printf '#!/bin/sh\nexit 0\n' > "$d/.git/hooks/pre-push"; chmod +x "$d/.git/hooks/pre-push" ;;
  esac
  echo "$d"
}

# Only this section; it runs last before the summary line.
gate_lines() {
  DOTFILES_REPO="$1" bash "$DOCTOR" 2>&1 | sed -n '/doctor: dotfiles push gate/,/^doctor: [0-9]/p'
}
expect() {  # expect <label> <repo> <ERE>
  local out; out="$(gate_lines "$2")"
  if printf '%s' "$out" | grep -Eq "$3"; then ok "$1"
  else bad "$1: $(printf '%s' "$out" | sed -n 2p)"; fi
}

expect "a wired gate reports OK and names the public and private remotes" \
  "$(make_repo armed armed)"   'OK +push gate armed for pub \(private: origin\)'
expect "a public remote with no gate reports FAIL" \
  "$(make_repo unwired unwired)" 'FAIL +pushes to pub are UNSCANNED'
expect "an unrelated pre-push is not mistaken for the gate" \
  "$(make_repo foreign foreign)" 'FAIL +pushes to pub are UNSCANNED'
expect "only private remotes needs no gate" \
  "$(make_repo private private)" 'OK +no public remote; nothing to gate \(private: origin\)'
mkdir -p "$T/plain"
expect "a directory that is not a checkout reports ABSENT" \
  "$T/plain" "ABSENT +no git checkout at $T/plain"

# Inert-lane guard: five cases, each must have asserted.
[ $((pass + fail)) -eq 5 ] || bad "ran $((pass + fail)) cases, want 5"
printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
