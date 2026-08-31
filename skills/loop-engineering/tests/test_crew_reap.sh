#!/usr/bin/env bash
# Contract fixtures for crew-reap. The safety gates matter more than the
# happy path: a regression here deletes a live session's checkout or a branch
# whose commits never landed.
set -uo pipefail
REAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/crew-reap"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
G() { git -c user.email=t@t.t -c user.name=t \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

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
ck "no roster keeps everything"    ""            'keep .*no roster supplied'
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
ck "bare-word roster fails closed"    ''           'cannot read roster'         --no-fetch --roster wt-peer-9d

build
ckjson "json: happy path" '.'       --target main --json "$TMP/r"
ckjson "json: error path" '.error'  --json "$TMP/nope"
ckjson "json: bad option" '.error'  --json --no-such-flag "$TMP/r"

# A roster matching NO worktree is operationally identical to no roster: the
# ownership gate voted on nothing. Reported live 2026-08-31 — a hand-typed
# roster of session names matched 0 of 2 worktrees and the output looked exactly
# like a run the gate had cleared.
build
ck "header reports the match count"   'wt-peer-9d' 'roster matched 1/'          --no-fetch
ck "inert gate is announced"          'nope-a,'    'ownership gate inert'        --no-fetch
ck "inert + apply is refused"         'nope-a,'    'APPLY REFUSED'               --no-fetch --apply
if [ -d "$TMP/wt-peer" ] && [ -d "$TMP/wt-landed" ]; then
  PASS=$((PASS+1)); printf '  PASS  inert refusal removed nothing\n'
else FAIL=$((FAIL+1)); printf '  FAIL  INERT REFUSAL STILL REMOVED SOMETHING\n'; fi

build
out=$(OWNERSHIP_INERT_OK=1 "$REAP" --target main --no-fetch --apply --roster 'nope-a,' "$TMP/r" 2>&1)
if printf '%s' "$out" | grep -q 'APPLY REFUSED'; then
  FAIL=$((FAIL+1)); printf '  FAIL  override did not lift the refusal\n'
else PASS=$((PASS+1)); printf '  PASS  OWNERSHIP_INERT_OK lifts the refusal\n'; fi

# A refusal must fire only when a removal is pending, and must be visible to a
# caller. Both reported live 2026-08-31.
build
# leave only worktrees that are kept for non-ownership reasons (unlanded, dirty),
# so nothing is reapable and the refusal has nothing to protect
G -C "$TMP/r" worktree remove --force "$TMP/wt-landed" >/dev/null 2>&1
G -C "$TMP/r" worktree remove --force "$TMP/wt-peer"   >/dev/null 2>&1
out=$("$REAP" --target main --no-fetch --apply --roster 'nope-a,' "$TMP/r" 2>&1); rc=$?
if printf '%s' "$out" | grep -q 'REFUSED'; then
  FAIL=$((FAIL+1)); printf '  FAIL  refused a run with nothing to reap\n'
else PASS=$((PASS+1)); printf '  PASS  no refusal when nothing is reapable\n'; fi
if [ "$rc" = 0 ]; then PASS=$((PASS+1)); printf '  PASS  no-op inert run exits 0\n'
else FAIL=$((FAIL+1)); printf '  FAIL  no-op inert run exited %s\n' "$rc"; fi

build
out=$("$REAP" --target main --no-fetch --apply --roster 'nope-a,' "$TMP/r" 2>&1); rc=$?
if [ "$rc" = 4 ]; then PASS=$((PASS+1)); printf '  PASS  refusal exits 4, distinct from 0 and 3\n'
else FAIL=$((FAIL+1)); printf '  FAIL  refusal exited %s, want 4\n' "$rc"; fi
if printf '%s' "$out" | grep -q 'wt-landed'; then
  PASS=$((PASS+1)); printf '  PASS  refusal names the worktrees examined\n'
else FAIL=$((FAIL+1)); printf '  FAIL  refusal does not name what it examined\n'; fi
if [ -d "$TMP/wt-landed" ]; then PASS=$((PASS+1)); printf '  PASS  refusal removed nothing\n'
else FAIL=$((FAIL+1)); printf '  FAIL  REFUSAL STILL REMOVED SOMETHING\n'; fi

build
ck "matching roster raises no warning" 'wt-peer-9d' 'roster matched 1/'          --no-fetch
out=$(printf 'wt-peer-9d\n' | "$REAP" --target main --no-fetch "$TMP/r" 2>&1)
if printf '%s' "$out" | grep -q 'gate inert'; then
  FAIL=$((FAIL+1)); printf '  FAIL  warned despite a matching roster\n'
else PASS=$((PASS+1)); printf '  PASS  no inert warning when the gate voted\n'; fi

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

# Exit codes are the caller contract (crew.md: capture before parsing).
# Assert them directly — the grep-only checks above would pass even if die()
# regressed to exit 0.
build
out=$("$REAP" --target main --no-fetch --roster /nope/nope "$TMP/r" 2>&1); rc=$?
if [ "$rc" = 1 ]; then PASS=$((PASS+1)); printf '  PASS  unreadable roster exits 1\n'
else FAIL=$((FAIL+1)); printf '  FAIL  unreadable roster exited %s, want 1\n' "$rc"; fi
out=$("$REAP" --target main --no-fetch --roster 'wt-peer-9d,' "$TMP/r" 2>&1); rc=$?
if [ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'DRY RUN'; then
  PASS=$((PASS+1)); printf '  PASS  dry run with a pending reap exits 3\n'
else FAIL=$((FAIL+1)); printf '  FAIL  dry-run pending reap exited %s, want 3\n' "$rc"; fi

# A detached-HEAD worktree cannot prove landed; it is kept even when its
# commit is fully present on the target.
build
G -C "$TMP/r" worktree add -q --detach "$TMP/wt-det" main
ck "detached HEAD kept"            'wt-peer-9d'  'keep +wt-det .*detached HEAD' --no-fetch
"$REAP" --target main --no-fetch --apply --roster 'wt-peer-9d,' "$TMP/r" >/dev/null 2>&1
if [ -d "$TMP/wt-det" ]; then PASS=$((PASS+1)); printf '  PASS  --apply preserves detached worktree\n'
else FAIL=$((FAIL+1)); printf '  FAIL  --apply REMOVED a detached worktree\n'; fi

# A failed branch delete degrades the row but still exits 3 — crew.md tells
# callers the exit code is not the whole verdict; lock that here.
build
touch "$TMP/r/.git/refs/heads/br-landed.lock"
out=$("$REAP" --target main --no-fetch --apply --roster 'wt-peer-9d,' "$TMP/r" 2>&1); rc=$?
rm -f "$TMP/r/.git/refs/heads/br-landed.lock"
if [ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'branch delete failed'; then
  PASS=$((PASS+1)); printf '  PASS  branch delete failure degrades the row, still exits 3\n'
else FAIL=$((FAIL+1)); printf '  FAIL  branch delete failure: rc=%s\n%s\n' "$rc" "$out"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
