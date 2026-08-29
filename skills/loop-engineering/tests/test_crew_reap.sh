#!/usr/bin/env bash
# Contract fixtures for crew-reap. The safety gates matter more than the
# happy path: a regression here deletes a live session's checkout or a branch
# whose commits never landed.
set -uo pipefail
REAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/crew-reap"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
G() { git -c user.email=t@t.t -c user.name=t "$@"; }

build() {  # fresh fixture: main + landed, ahead, peer, dirty worktrees
  rm -rf "$TMP/r" "$TMP"/wt-*
  G init -q --initial-branch=main "$TMP/r"
  ( cd "$TMP/r" && echo a > a.txt && G add -A && G commit -qm base )
  for w in landed ahead peer dirty; do
    G -C "$TMP/r" worktree add -q -b "br-$w" "$TMP/wt-$w"
  done
  ( cd "$TMP/wt-ahead" && echo x > x.txt && G add -A && G commit -qm work )
  echo d > "$TMP/wt-dirty/d.txt"
}

ck() {  # ck <name> <roster> <pattern> [args...]
  local name=$1 roster=$2 pat=$3; shift 3
  local out; out=$(printf '%s' "$roster" | "$REAP" --target main "$TMP/r" "$@" 2>&1)
  if printf '%s' "$out" | grep -Eq "$pat"; then
    PASS=$((PASS+1)); printf '  PASS  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  %s\n     wanted /%s/ in:\n%s\n' "$name" "$pat" "$out"
  fi
}

build
# The gates, one case each.
ck "no roster keeps everything"    ""            '0 reapable, 4 kept'
ck "live agent worktree kept"      'wt-peer-9d'  'keep +wt-peer .*live agent'
ck "unlanded branch kept"          'wt-peer-9d'  'keep +wt-ahead .*not in main'
ck "dirty worktree kept"           'wt-peer-9d'  'keep +wt-dirty .*uncommitted'
ck "landed branch is reapable"     'wt-peer-9d'  'reap +wt-landed .*0 commits ahead'
ck "exact roster name matches"     'wt-peer'     'keep +wt-peer .*live agent'

# Dry run must not mutate.
printf 'wt-peer-9d\n' | "$REAP" --target main "$TMP/r" >/dev/null 2>&1
n=$(G -C "$TMP/r" worktree list | wc -l | tr -d ' ')
if [ "$n" = 5 ]; then PASS=$((PASS+1)); printf '  PASS  dry run removes nothing\n'
else FAIL=$((FAIL+1)); printf '  FAIL  dry run removed something (%s worktrees left)\n' "$n"; fi

# --apply removes only the landed one, and keeps the unlanded branch.
printf 'wt-peer-9d\n' | "$REAP" --target main --apply "$TMP/r" >/dev/null 2>&1
if ! G -C "$TMP/r" rev-parse --verify -q br-landed >/dev/null; then
  PASS=$((PASS+1)); printf '  PASS  apply deletes the landed branch\n'
else FAIL=$((FAIL+1)); printf '  FAIL  landed branch survived apply\n'; fi
if G -C "$TMP/r" rev-parse --verify -q br-ahead >/dev/null; then
  PASS=$((PASS+1)); printf '  PASS  apply keeps the unlanded branch\n'
else FAIL=$((FAIL+1)); printf '  FAIL  UNLANDED BRANCH DELETED\n'; fi
if [ -d "$TMP/wt-peer" ]; then
  PASS=$((PASS+1)); printf '  PASS  apply keeps the live peer worktree\n'
else FAIL=$((FAIL+1)); printf '  FAIL  LIVE PEER WORKTREE DELETED\n'; fi

# Porcelain `worktree <path>` is not awk-field-safe: a space in the path must
# still enumerate. A 0-ahead branch is reapable when the roster does not own it.
build
G -C "$TMP/r" worktree add -q -b "br-space" "$TMP/wt spaced"
ck "worktree path with a space is enumerated" 'wt-peer-9d' 'reap +wt spaced'

# --json answers in JSON on every path. Capture BEFORE parsing: crew-reap exits
# 3 when there is something to reap, and under `set -o pipefail` a pipeline into
# jq would report that as failure even though the JSON is well formed.
ckjson() {  # ckjson <name> <filter> [args...]
  local name=$1 filter=$2; shift 2
  local out; out=$(printf 'x\n' | "$REAP" "$@" 2>/dev/null)
  if printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf '  PASS  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  %s -> %s\n' "$name" "$out"
  fi
}

# The landed test is only as fresh as the target ref. A stale one fails safe but
# silently, and the message reads as unlanded work. The header must expose the
# resolved SHA and whether it was fetched, so a stale reading is visible.
build
ck "header names the resolved target" 'wt-peer-9d' 'target=main@[0-9a-f]+ \(' --no-fetch
ck "no-fetch is disclosed"            'wt-peer-9d' 'reading may be stale'      --no-fetch
printf 'wt-peer-9d\n' > "$TMP/roster.txt"
ck "roster flag matches stdin"        ''           'keep +wt-peer .*live agent' --no-fetch --roster "$TMP/roster.txt"
ck "roster accepts an inline list"    ''           'keep +wt-peer .*live agent' --no-fetch --roster 'wt-peer-9d,other'
ck "unreadable roster rejected"       ''           'cannot read roster'         --roster /nope/nope

# Bare stdin is bounded across the whole stream, not five seconds per line.
# The seventh writer iteration should hit the closed pipe after the deadline.
started=$SECONDS
slow_out=$(
  for i in 1 2 3 4 5 6 7; do sleep 1; printf 'agent-%s\n' "$i"; done |
    "$REAP" --target main --no-fetch "$TMP/r" 2>&1
) || true
elapsed=$((SECONDS - started))
if [ "$elapsed" -le 6 ]; then
  PASS=$((PASS+1)); printf '  PASS  bare stdin has one total timeout\n'
else
  FAIL=$((FAIL+1)); printf '  FAIL  bare stdin timeout reset per line (%ss)\n' "$elapsed"
fi

build
ckjson "json: happy path" '.'       --target main --json "$TMP/r"
ckjson "json: error path" '.error'  --json "$TMP/nope"
ckjson "json: bad option" '.error'  --json --no-such-flag "$TMP/r"

# Exit 3 is a verdict, not an error. Lock BOTH directions: capture-then-parse
# must read it correctly, and the piped form must still fail — otherwise this
# fixture stops guarding the documented trap. See references/examples.md §6.
build
{
  set -uo pipefail
  raw=$(printf 'x\n' | "$REAP" --target main --json --no-fetch "$TMP/r" 2>/dev/null) || true
  cur=$(printf '%s' "$raw" | jq -S -c '{reaped}' 2>/dev/null) || cur='{"error":"unparseable"}'
  if printf '%s' "$cur" | jq -e '.reaped >= 1' >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf '  PASS  capture-then-parse survives exit 3\n'
  else
    FAIL=$((FAIL+1)); printf '  FAIL  capture-then-parse survives exit 3 (got %s)\n' "$cur"
  fi
  old=$( { set -o pipefail
    printf 'x\n' | "$REAP" --target main --json --no-fetch "$TMP/r" 2>/dev/null | jq -S -c '{reaped}' 2>/dev/null
  } ) || old='{"error":"unparseable"}'
  if [ "$old" = '{"error":"unparseable"}' ]; then
    PASS=$((PASS+1)); printf '  PASS  piped form still false-positives on exit 3\n'
  else
    FAIL=$((FAIL+1)); printf '  FAIL  piped form no longer locks the trap (got %s)\n' "$old"
  fi
}

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
