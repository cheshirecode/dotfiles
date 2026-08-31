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

prog() {  # prog <body-sections>  program with NO orientation frontmatter keys
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
ck "program with no tasks anywhere is caught" "$(warns "neither a 'tasks:' field")" 1

prog '## Tasks

- [ ] [[child-one]]'
ck "program with no goal anywhere is caught"      "$(warns "neither a 'goal:' field")" 1
ck "program with no objective anywhere is caught" "$(warns "neither a 'objective:' field")" 1

# Orientation may live in FRONTMATTER instead of body sections. A hand-maintained
# program keeps goal:/objective:/tasks: as fields and organises its body as
# Context / Findings / Scope / Work items / Verification. Demanding the body
# sections flagged three warnings on exactly such a file in the live corpus —
# the first version of this check swapped one false-positive class for another.
{ printf -- '---\nslug: prog\nowner: tester\nstatus: draft\nkind: project\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\ngoal: "g"\nobjective: "o"\ntasks:\n  - slug: child-one\n---\n\n## Context\n\nc\n\n## Findings\n\nf\n\n## Next\n\n- [ ] x\n'
} > people/tester/active/prog.md
ck "frontmatter goal/objective/tasks satisfies it" "$(warns 'kind: project) has neither')" 0

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
