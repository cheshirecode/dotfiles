#!/usr/bin/env bash
# `kind: project` files are programs, not tasks. `project.sh new` emitted them
# with ## Goal / ## Objective / ## Tasks and no ## Context, so every program
# warned the moment the generator wrote it (reported live 2026-08-31: 3 of one
# clone's 8 remaining warnings were generator output).
#
# The fix must not be a blanket exemption. Assert BOTH directions: a well-formed
# program is clean, AND a program missing a section it genuinely needs is still
# caught. An exemption tested only by its silence is a hole.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
unset WORKLOG_REPO WORKLOG_LDAP || true
export WORKLOG_REPO="$TMP"
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi; }

cd "$TMP"; git init -q
git config user.email tester@example.com; git config user.name Tester
mkdir -p people/tester/active

warns() {  # warns <pattern> -> count of matching warning lines
  python3 "$ROOT/bin/_lint.py" 2>&1 | grep -c "$1" || true
}

prog() {  # prog <body-sections...>  writes the program file
  { printf -- '---\nslug: prog\nowner: tester\nstatus: draft\nkind: project\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n'
    printf '%s\n' "$1"
    printf '\n## Next\n\n- [ ] x\n'
  } > people/tester/active/prog.md
}

# The real generator output shape: Goal/Objective/Tasks, deliberately no Context.
prog '## Goal

Ship it.

## Objective

Measurably shipped.

## Tasks

- [ ] [[child-one]]'
ck "well-formed program needs no ## Context" "$(warns 'missing ## Context')" 0
ck "well-formed program raises no program warning" "$(warns 'kind: project) missing')" 0

# A program missing a section it DOES need is still caught — the exemption
# replaced the task rule, it did not remove the checking.
prog '## Goal

Ship it.

## Objective

Measurably shipped.'
ck "program missing ## Tasks is caught" "$(warns 'missing ## Tasks')" 1

prog '## Tasks

- [ ] [[child-one]]'
ck "program missing ## Goal is caught"      "$(warns 'missing ## Goal')" 1
ck "program missing ## Objective is caught" "$(warns 'missing ## Objective')" 1

# ## Next is required of programs too — that rule was never task-specific.
{ printf -- '---\nslug: prog\nowner: tester\nstatus: draft\nkind: project\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n## Goal\n\ng\n\n## Objective\n\no\n\n## Tasks\n\n- [ ] x\n'
} > people/tester/active/prog.md
ck "program still needs ## Next" "$(warns 'missing ## Next')" 1

# An ordinary task is unaffected: it still owes ## Context.
printf -- '---\nslug: plain\nowner: tester\nstatus: in-progress\nkind: impl\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n## Next\n\n- [ ] x\n' \
  > people/tester/active/plain.md
rm -f people/tester/active/prog.md
ck "a non-program task still owes ## Context" "$(warns 'missing ## Context')" 1

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
