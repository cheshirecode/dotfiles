#!/usr/bin/env bash
# An optional identifier written as an explicit null is not the same as absent.
# yaml.safe_load turns `tracker: null` into None, so a YAML consumer cannot tell
# the two apart — but a line-oriented reader sees the key present with the
# string "null" and counts the task as tracked. Measured 2026-09-18: 17 active
# tasks carried `tracker: null` against 68 that omitted the key, so a consumer
# testing presence rather than value overcounted the tracked set by 17.
# Assert the warning fires for an explicit null, stays silent when the key is
# omitted or carries a real id, and does not pester frozen archive/ history.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

mkdir -p "$TMP/wl/people/tester/active" "$TMP/wl/people/tester/archive"
cd "$TMP/wl" && git init -q --initial-branch=main

task() {  # task <dir> <file> <extra-frontmatter-line> <status>
  { printf -- '---\nslug: %s\nstatus: %s\nkind: impl\nproject: none\nrepos: []\n' "$2" "$4"
    [ -n "$3" ] && printf -- '%s\n' "$3"
    printf -- 'last_updated: 2026-09-18\nnext_action: "x"\n---\n\n## Context\nc\n\n## Next\n- [ ] x\n'
  } > "people/tester/$1/$2.md"
}
# Hermetic: BASH_ENV / direnv / a per-clone .envrc export WORKLOG_REPO AFTER the
# per-command assignment, so without the unsets this lints the real vault and
# every assertion measures somebody else's tasks.
run() { OUT=$(env -u BASH_ENV -u WORKLOG_NS -u WORKLOG_LDAP -u WORKLOG_REPO \
              WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester bash "$ROOT/bin/lint.sh" 2>&1); }
saw() { printf '%s' "$OUT" | grep -q "$1"; }

# 1. explicit null on an active task warns
task active thing 'tracker: null' in-progress
run
saw "tracker: is present but empty" && ck "explicit null warns" pass pass || ck "explicit null warns" fail pass
saw "omit the key entirely" && ck "warning says what to do instead" pass pass || ck "warning says what to do instead" fail pass

# 2. empty string is the same defect
task active thing 'tracker: ""' in-progress
run
saw "tracker: is present but empty" && ck "empty string warns" pass pass || ck "empty string warns" fail pass

# 3. a real id is clean
task active thing 'tracker: SPLUS-1234' in-progress
run
saw "tracker: is present but empty" && ck "real id is clean" fail pass || ck "real id is clean" pass pass

# 4. omitting the key entirely is clean — that is the prescribed form
task active thing '' in-progress
run
saw "tracker: is present but empty" && ck "omitted key is clean" fail pass || ck "omitted key is clean" pass pass

# 5. same rule covers linear:, which already carried the convention in AGENTS.md
task active thing 'linear: null' in-progress
run
saw "linear: is present but empty" && ck "linear: null warns too" pass pass || ck "linear: null warns too" fail pass

# 6. archive/ is frozen history and must stay quiet
rm -f people/tester/active/thing.md
task archive oldthing 'tracker: null' archived
run
saw "tracker: is present but empty" && ck "archive/ is not pestered" fail pass || ck "archive/ is not pestered" pass pass

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
