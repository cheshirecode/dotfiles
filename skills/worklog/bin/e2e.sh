#!/usr/bin/env bash
# E2E sanity check for a freshly-cloned _worklog. Exercises the helpers
# end-to-end: namespace setup, task creation, checkpoint, lint, archive,
# export/import round-trip, regression tests, hooks, negative paths.
#
# Designed to run inside Dockerfile.{debian,alpine} where:
#   - cwd is the worklog repo root
#   - USER=ldap-test is set
#   - origin remote points at a local bare repo
#
# Each step asserts exit code OR a substring in captured output. First
# failure prints which step + last 30 lines of output, then exits 1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WORKLOG_BIN="${WORKLOG_BIN:-$SCRIPT_DIR}"
export WORKLOG_REPO="${WORKLOG_REPO:-$PWD}"

if [[ -d skills/worklog && "${WORKLOG_E2E_ALLOW_SOURCE:-0}" != "1" ]]; then
  echo "e2e: refusing to run from the dotfiles/source tree; run in a disposable _worklog data repo or set WORKLOG_E2E_ALLOW_SOURCE=1" >&2
  exit 2
fi

step=""
out_file=$(mktemp)
trap 'rm -f "$out_file"' EXIT

fail() {
  echo "===== E2E FAIL: $step ====="
  echo "--- last 30 lines of step output ---"
  tail -30 "$out_file"
  echo "===== exit 1 ====="
  exit 1
}

run() {
  step="$1"; shift
  printf '\n[step] %s\n' "$step"
  if ! "$@" >"$out_file" 2>&1; then
    fail
  fi
}

assert_contains() {
  local needle="$1"
  if ! grep -qF -- "$needle" "$out_file"; then
    echo "===== E2E FAIL: '$needle' not found in step '$step' output ====="
    tail -30 "$out_file"
    exit 1
  fi
}

LDAP="${USER:-ldap-test}"
NS="people/$LDAP/active"

# --- 1. namespace + tools -----------------------------------------------
run "preflight: bash + python3 + perl + git + ripgrep + jq present" bash -c '
  command -v bash python3 perl git rg jq >/dev/null'

run "namespace: create people/$LDAP/{active,archive}" bash -c "
  mkdir -p people/$LDAP/active people/$LDAP/archive
  touch people/$LDAP/archive/.gitkeep"

# --- 2. seed three tasks ------------------------------------------------
cat > "$NS/seed-impl.md" <<EOF
---
slug: seed-impl
status: in-progress
kind: impl
repos: [_worklog]
project: e2e
created: 2026-04-26
last_updated: 2026-04-26
next_action: "Stub task that the e2e exercises end-to-end."
---

## Context
E2E seed.

## Next
- [ ] e2e exercises this
EOF

cat > "$NS/seed-blocked.md" <<EOF
---
slug: seed-blocked
status: blocked
kind: impl
repos: [_worklog]
project: e2e
created: 2026-04-26
last_updated: 2026-04-26
next_action: "Waiting on e2e suite to validate FSM."
---

## Context
E2E blocked-state fixture.

## Next
- [ ] verify FSM contract holds
EOF

cat > "$NS/seed-design.md" <<EOF
---
slug: seed-design
status: draft
kind: design
repos: [_worklog]
project: e2e
created: 2026-04-26
last_updated: 2026-04-26
next_action: "Stub design fixture; checkpoint then archive."
---

## Context
E2E design fixture.

## Next
- [ ] decide
EOF

run "stage seed tasks" git add "$NS"
run "commit seed tasks" git -c commit.gpgsign=false commit -q -m "e2e: seed 3 tasks"

# --- 3. lint ------------------------------------------------------------
run "lint per-file (no errors expected)" bin/lint.sh
assert_contains "0 errors"

run "lint --cross-task (no errors expected)" bin/lint.sh --cross-task
assert_contains "0 errors"

# --- 4. checkpoint ------------------------------------------------------
run "checkpoint seed-impl --status=in-review" \
  bin/checkpoint.sh seed-impl --status=in-review --next='moved to review'
assert_contains "pushed seed-impl"

# --- 5. archive ---------------------------------------------------------
run "archive seed-design --reason=shipped" \
  bin/archive.sh seed-design --reason=shipped --summary='e2e fixture; archived to verify the path.'
assert_contains "pushed seed-design"

run "verify seed-design now in archive/" \
  test -f "people/$LDAP/archive/seed-design.md"

# --- 6. export/import round-trip ----------------------------------------
run "export-setup writes artifact" bin/export-setup.sh

# Find the freshest export artifact
artifact="$(ls -t /tmp/worklog-setup-*.txt 2>/dev/null | head -1)"
[[ -n "$artifact" ]] || { step="export-setup output"; fail; }

run "artifact has sentinel files" grep -c '^=====WORKLOG-EXPORT-FILE=====' "$artifact"
assert_contains ""  # any count > 0 — grep -c returns 0 only on empty

# --- 7. regression tests ------------------------------------------------
run "tests/export/test_scrubber.sh" tests/export/test_scrubber.sh
run "tests/frontmatter/test_round_trip.sh" tests/frontmatter/test_round_trip.sh

# --- 8. hooks: install-hooks (skips Claude side; sets git core.hooksPath)
# Claude settings.json doesn't exist in container; install-hooks will fail
# the Claude-side write but should still set core.hooksPath. Run with --write
# and tolerate the Claude path failure (set CLAUDE_SETTINGS to a tmp file).
run "install-hooks --write (fake claude settings)" bash -c '
  echo "{}" > /tmp/claude-settings.json
  CLAUDE_SETTINGS=/tmp/claude-settings.json bin/install-hooks.sh --write'
assert_contains "core.hooksPath"

run "git config core.hooksPath set" bash -c '
  [[ "$(git config --get core.hooksPath)" == "bin/git-hooks" ]]'

# --- 9. pre-commit hook fires on a touched file -------------------------
echo "" >> bin/checkpoint.sh
git add bin/checkpoint.sh
run "pre-commit hook on staged bin script" bin/git-hooks/pre-commit
git restore --staged bin/checkpoint.sh
git checkout bin/checkpoint.sh

# --- 10. post-commit advisory + TTL stamp -------------------------------
rm -f .cache/cross-task.stamp
echo "" >> "$NS/seed-impl.md"
git add "$NS/seed-impl.md"
run "commit triggers post-commit" git -c commit.gpgsign=false commit -q -m "e2e: trigger post-commit"
run "post-commit ran (.cache/cross-task.stamp exists)" \
  test -f .cache/cross-task.stamp

# --- 11. pre-commit-scan.sh: strict mode blocks seeded ghp_ token -------
echo "leaked <REDACTED:SECRET> token" > "$NS/seed-token-test.md"
git add "$NS/seed-token-test.md"
if WORKLOG_STRICT_SCAN=1 bin/pre-commit-scan.sh >"$out_file" 2>&1; then
  step="pre-commit-scan strict should have blocked seeded ghp_ token"
  fail
fi
assert_contains "SECRET_GH_PAT"
assert_contains "blocking"
git reset -q HEAD -- "$NS/seed-token-test.md" || true
rm -f "$NS/seed-token-test.md"

# --- 12. verify_provenance: mismatch path errors ------------------------
rm -f .cache/provenance-verified
git config user.email "wrong-user@example.com"
if ( . bin/_lib.sh && verify_provenance ) >"$out_file" 2>&1; then
  step="verify_provenance should have failed with mismatched git email"
  fail
fi
assert_contains "LDAP/email mismatch"
assert_contains "Bypass"
git config user.email "${LDAP}@example.com"
run "verify_provenance: match path emits sentinel" bash -c '
  rm -f .cache/provenance-verified
  . bin/_lib.sh && verify_provenance && test -f .cache/provenance-verified'

# --- 13. audit.sh: composite report runs all sections clean -------------
run "audit.sh runs without error" bin/audit.sh
assert_contains "Stale active tasks"
assert_contains "Blocked"
assert_contains "In-review"
assert_contains "Cross-task drift"

# --- 14. log-digest.sh: basic + JSON parse ------------------------------
run "log-digest.sh produces output" bin/log-digest.sh --since=30.days.ago
run "log-digest.sh --format=json parses" bash -c '
  bin/log-digest.sh --since=30.days.ago --format=json | python3 -c "import json,sys; json.load(sys.stdin)"'

# --- 15. commit-msg hook: trailer-vs-frontmatter + slug-validate ---------
# Valid match (seed-impl is in active/ with status: in-review post step 7)
HOOK_MSG=$(mktemp)
cat > "$HOOK_MSG" <<MSG
e2e: hook test

Worklog-Slug: seed-impl
Worklog-Status: in-review
MSG
run "commit-msg hook accepts matching trailer" bin/git-hooks/commit-msg "$HOOK_MSG"

# Typo slug must reject
cat > "$HOOK_MSG" <<MSG
e2e: hook test

Worklog-Slug: seed-impl-typo-xyzzy
MSG
if bin/git-hooks/commit-msg "$HOOK_MSG" >"$out_file" 2>&1; then
  step="commit-msg should have rejected typo Worklog-Slug"
  fail
fi
assert_contains "does not resolve"

# Mismatched status must reject
cat > "$HOOK_MSG" <<MSG
e2e: hook test

Worklog-Slug: seed-impl
Worklog-Status: blocked
MSG
if bin/git-hooks/commit-msg "$HOOK_MSG" >"$out_file" 2>&1; then
  step="commit-msg should have rejected status mismatch"
  fail
fi
assert_contains "does not match frontmatter"
rm -f "$HOOK_MSG"

# --- 16. checkpoint-batch + slug.sh ------------------------------------
# Use the existing seed-impl + seed-design tasks. Batch updates both.
echo '[{"slug":"seed-impl","next":"e2e batch test"},{"slug":"seed-design","next":"e2e batch test 2"}]' \
  | run "checkpoint-batch updates 2 tasks atomically" bin/checkpoint-batch.sh
assert_contains "pushed 2 tasks"

# slug.sh: exact match
run "slug.sh exact match" bin/slug.sh seed-impl
assert_contains "seed-impl"

# slug.sh: typo with substring
run "slug.sh substring match" bin/slug.sh impl
assert_contains "seed-impl"

# slug.sh: no match exits 1
if bin/slug.sh xyzzyplover-no-match >"$out_file" 2>&1; then
  step="slug.sh should have exited 1 for no match"
  fail
fi

# --- 17. checkpoint --status=archived must hard-fail with archive.sh hint
if bin/checkpoint.sh seed-impl --status=archived >"$out_file" 2>&1; then
  step="checkpoint --status=archived should have failed"
  fail
fi
assert_contains "wrong tool"
assert_contains "bin/archive.sh seed-impl --reason="

# --- 18. checkpoint staged-scope guard: refuse unexpected staged paths
echo "stray edit" >> README.md
git add README.md
if bin/checkpoint.sh seed-impl --next="guard test" >"$out_file" 2>&1; then
  step="checkpoint should have refused unexpected staged path README.md"
  fail
fi
assert_contains "unexpected staged paths"
assert_contains "WORKLOG_CHECKPOINT_FORCE=1"
git restore --staged README.md
git checkout -- README.md

# --- 19. negative path: induce a YAML colon and verify lint catches -----
cat > "$NS/seed-broken.md" <<EOF
---
slug: seed-broken
status: blocked
kind: impl
repos: [_worklog]
project: e2e
created: 2026-04-26
last_updated: 2026-04-26
next_action: bare colon: makes YAML angry
---

## Context
broken
EOF
if bin/lint.sh --file="$NS/seed-broken.md" >"$out_file" 2>&1; then
  step="negative-path lint should have failed but did not"
  fail
fi
rm "$NS/seed-broken.md"

echo
echo "===== E2E PASS ====="
