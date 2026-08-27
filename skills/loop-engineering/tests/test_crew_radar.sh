#!/usr/bin/env bash
# Fixtures for bin/crew-radar. Builds throwaway repos in a temp dir; no network.
set -uo pipefail
RADAR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/crew-radar"
PASS=0; FAIL=0
ok(){   printf "  PASS  %s\n" "$1"; PASS=$((PASS+1)); }
bad(){  printf "  FAIL  %s\n" "$1"; FAIL=$((FAIL+1)); }
ck(){ # name expected_exit expected_grep [args...]
  local name=$1 xc=$2 pat=$3; shift 3
  local out rc
  out=$("$RADAR" "$@" 2>&1); rc=$?
  if [ "$rc" != "$xc" ]; then bad "$name (exit $rc, want $xc)"; printf '%s\n' "$out" | sed 's/^/        /'; return; fi
  if [ -n "$pat" ] && ! grep -Eq "$pat" <<<"$out"; then bad "$name (no match /$pat/)"; printf '%s\n' "$out" | sed 's/^/        /'; return; fi
  ok "$name"
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
G(){ git -c user.email=radar@test -c user.name=radar -c init.defaultBranch=master \
        -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

# --- fixture: base repo with two feature worktrees -------------------------
R=$TMP/repo
G init -q "$R"
cd "$R" || exit 1
printf 'a\n' > shared.txt; printf 'b\n' > solo.txt
G add -A; G commit -qm init
G branch -q feat-a; G branch -q feat-b; G branch -q feat-c
G worktree add -q "$TMP/wa" feat-a
G worktree add -q "$TMP/wb" feat-b

echo "== crew-radar fixtures =="

# 1. clean: each worktree edits a different file
printf 'a2\n' > "$TMP/wa/solo.txt"
printf 'b2\n' > "$TMP/wb/only-b.txt"
ck "clean: disjoint edits" 0 "clean — no overlapping paths" --base master "$R"

# 2. warn: both worktrees dirty on the same path
printf 'a3\n' > "$TMP/wa/shared.txt"
printf 'b3\n' > "$TMP/wb/shared.txt"
ck "warn: two dirty worktrees"          2 "^warn +shared\.txt" --base master "$R"
ck "warn: both owners marked dirty"     2 "feat-a\[dirty\].*feat-b\[dirty\]" --base master "$R"
ck "warn: --quiet is silent"            2 "^$" --quiet --base master "$R"
ck "warn: json reports severity"        2 '"severity":"warn","path":"shared\.txt"' --json --base master "$R"

# 3. warn: uncommitted edit in main worktree vs committed change in a worktree
G -C "$TMP/wa" checkout -q -- shared.txt
rm -f "$TMP/wb/shared.txt"; G -C "$TMP/wb" checkout -q -- shared.txt
printf 'committed\n' > "$TMP/wa/shared.txt"
G -C "$TMP/wa" commit -qam "feat-a touches shared"
printf 'local\n' > "$R/shared.txt"       # dirty in the MAIN worktree
ck "warn: main dirty vs worktree commit" 2 "^warn +shared\.txt" --base master "$R"
G -C "$R" checkout -q -- shared.txt

# 4. info: feat-b stacks on feat-a, so both branches legitimately carry the file
G -C "$TMP/wb" merge -q --no-edit feat-a
ck "info: stacked branches"             0 "^info +shared\.txt" --base master "$R"
ck "info: solo.txt stacked too"         0 "^info +solo\.txt" --base master "$R"
ck "info: exit 0, nothing escalated"    0 "0 warn, 2 info" --base master "$R"
ck "info: --strict escalates"           2 "^info +shared\.txt" --strict --base master "$R"

# 5. plumbing
ck "help exits 0"                       0 "flag files that more than one" --help
ck "bad option rejected"                1 "unknown option" --nope
ck "non-repo rejected"                  1 "not inside a git repository" "$TMP"
ck "bad base rejected"                  1 "base ref not found" --base no/such/ref "$R"

printf "\n  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
