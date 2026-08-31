#!/usr/bin/env bash
# `people/<ldap>/artifacts/` holds content a task body links to, not tasks.
# Two separate assertions, because the lint had two separate defects: it
# reported the directory as unknown, AND it enrolled the files in task_paths so
# they were validated as tasks. The second is the one that bites — an artifact
# named after the task it belongs to collides in the duplicate-slug check.
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
mkdir -p people/tester/active people/tester/artifacts people/tester/transcripts

cat > people/tester/active/splus-1-thing.md <<'EOF'
---
slug: splus-1-thing
owner: tester
status: in-progress
kind: impl
project: none
repos: []
last_updated: 2026-08-31
next_action: "do the thing"
---

## Context

A real task.

## Next

- [ ] do the thing
EOF

# Same stem as the task above: under the old behaviour this was parsed as a task
# and reported as a duplicate slug that does not exist.
printf '# Monitor drafts for splus-1\n\nNo frontmatter. Not a task.\n' \
  > people/tester/artifacts/splus-1-thing.md
printf '# Findings\n\nAlso not a task.\n' > people/tester/artifacts/notes.md
printf '# A transcript\n' > people/tester/transcripts/session.md

out=$(python3 "$ROOT/bin/_lint.py" 2>&1 || true)

printf '%s' "$out" | grep -q "unknown task state directory 'people/tester/artifacts'" \
  && ck "artifacts is not reported as an unknown state dir" fail pass \
  || ck "artifacts is not reported as an unknown state dir" pass pass

printf '%s' "$out" | grep -qi "duplicate" \
  && ck "artifact sharing a task's stem is not a duplicate slug" fail pass \
  || ck "artifact sharing a task's stem is not a duplicate slug" pass pass

scanned=$(printf '%s' "$out" | sed -n 's/^Scanned \([0-9]*\) task files.*/\1/p')
ck "only the real task is counted" "${scanned:-0}" 1

errs=$(printf '%s' "$out" | sed -n 's/.*— \([0-9]*\) errors.*/\1/p')
ck "clean repo lints with 0 errors" "${errs:-x}" 0

# An genuinely unknown directory must STILL be reported — the fix exempts named
# content dirs, it does not stop flagging layout drift.
mkdir -p people/tester/wat && printf '# stray\n' > people/tester/wat/x.md
out2=$(python3 "$ROOT/bin/_lint.py" 2>&1 || true)
printf '%s' "$out2" | grep -q "unknown task state directory 'people/tester/wat'" \
  && ck "an actually-unknown dir is still reported" pass pass \
  || ck "an actually-unknown dir is still reported" fail pass

# A slug inside structured content is not a task reference. `decision-engine`
# is both a repo and a task slug here, and --fix-related wrote false relations
# from a version table and a fenced clone line (live 2026-08-31).
mkdir -p people/tester/active
cat > people/tester/active/decision-engine.md <<'TASK'
---
slug: decision-engine
owner: tester
status: in-progress
kind: impl
project: none
repos: []
last_updated: 2026-08-31
next_action: "x"
---

## Context

Slug that collides with a repo name.

## Next

- [ ] x
TASK

mention() {
  printf -- '---\nslug: mentions\nowner: tester\nstatus: in-progress\nkind: impl\nproject: none\nrepos: []\nlast_updated: 2026-08-31\nnext_action: "x"\n---\n\n## Context\n\n%s\n\n## Next\n\n- [ ] x\n' "$1" > people/tester/active/mentions.md
  python3 "$ROOT/bin/_lint.py" --cross-task 2>&1 | grep -c "body mentions slug 'decision-engine'" || true
}
ck "table row is not a task reference"    "$(mention '| decision-engine | 1.2 |')" 0
ck "fenced block is not a reference"      "$(mention '```
decision-engine x
```')" 0
ck "prose reference still warns"          "$(mention 'blocked on decision-engine')" 1
rm -f people/tester/active/mentions.md people/tester/active/decision-engine.md

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
