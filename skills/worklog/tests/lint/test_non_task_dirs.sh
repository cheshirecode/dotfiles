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

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
