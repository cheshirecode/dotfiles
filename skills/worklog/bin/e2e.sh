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
# This suite predates the skill/data split: every step below invokes bin/*.sh
# by RELATIVE path, asserts core.hooksPath == "bin/git-hooks", and appends to a
# tracked bin/checkpoint.sh then restores it with `git checkout`. All of that
# holds only when bin/ lives INSIDE the repo under test, which stopped being
# the layout when the skill moved out of the data repo. The suite has not run
# since.
#
# So it builds that layout itself now instead of asking the caller for a
# WORKLOG_REPO it will then mutate. It used to default WORKLOG_REPO to $PWD:
# run it from the skill directory -- the obvious place, right beside the
# script -- and it created people/<user>/, COMMITTED three seed tasks into the
# skills repo, and only failed four steps later with "resolve_worklog_repo:
# ... is not a git repo". Observed 2026-09-03, commit "e2e: seed 3 tasks"
# landed in the dotfiles repo and had to be reset out. Mutating before
# validating is how a test damages the thing it was run to protect.
#
# E2E_KEEP=1 leaves the scratch tree for inspection.
if [[ -z "${WORKLOG_REPO:-}" ]]; then
  E2E_SCRATCH="$(mktemp -d -t worklog-e2e-XXXXXX)"
  export WORKLOG_REPO="$E2E_SCRATCH/repo"
  mkdir -p "$WORKLOG_REPO" "$E2E_SCRATCH/nohooks"
  cp -R "$SCRIPT_DIR" "$WORKLOG_REPO/bin"
  # Steps below also invoke tests/*.sh by relative path.
  [[ -d "$SCRIPT_DIR/../tests" ]] && cp -R "$SCRIPT_DIR/../tests" "$WORKLOG_REPO/tests"
  (
    cd "$WORKLOG_REPO"
    git init -q .
    # The email decides the namespace: _lib.sh::resolve_ldap derives LDAP from
    # it, while the steps below use $USER. A mismatch put the seed tasks in
    # people/$USER/ and sent checkpoint.sh looking in people/e2e/.
    git config user.email "${USER:-ldap-test}@example.com"
    git config user.name "worklog-e2e"
    # Isolate from any globally-configured core.hooksPath; step 8 sets its own.
    git config core.hooksPath "$E2E_SCRATCH/nohooks"
    mkdir -p people
    touch people/.gitkeep
    git add -A
    git commit -q -m "e2e: scratch base"
    # checkpoint.sh pulls and pushes, so the scratch needs an upstream. A local
    # bare repo keeps every push in the scratch tree and off any real remote.
    git init -q --bare "$E2E_SCRATCH/origin.git"
    git remote add origin "$E2E_SCRATCH/origin.git"
    git push -q -u origin HEAD
    # Seeding is done, so stop shadowing hooks: point at the repo's own
    # bin/git-hooks, which is the state step 8 installs and step 10 relies on.
    # Leaving the empty nohooks dir in force made the chained .git/hooks
    # unreachable and the post-commit stamp never appeared.
    git config core.hooksPath bin/git-hooks
  )
fi

# Whether supplied or self-built, refuse to write into something that is not a
# worklog data repo.
if [[ ! -e "$WORKLOG_REPO/.git" ]]; then
  echo "e2e: WORKLOG_REPO=$WORKLOG_REPO is not a git repo." >&2
  echo "  This test writes and commits into it. Unset WORKLOG_REPO to let e2e" >&2
  echo "  build its own scratch repo." >&2
  exit 1
fi
if [[ ! -d "$WORKLOG_REPO/people" ]]; then
  echo "e2e: WORKLOG_REPO=$WORKLOG_REPO has no people/ — not a worklog data repo." >&2
  echo "  The skill directory is not the data repo; they were split. Refusing to" >&2
  echo "  create and commit seed tasks into a source checkout." >&2
  exit 1
fi
cd "$WORKLOG_REPO"

if [[ -d skills/worklog && "${WORKLOG_E2E_ALLOW_SOURCE:-0}" != "1" ]]; then
  echo "e2e: refusing to run from the dotfiles/source tree; run in a disposable _worklog data repo or set WORKLOG_E2E_ALLOW_SOURCE=1" >&2
  exit 2
fi

step=""
out_file=$(mktemp)
# ONE trap owns EXIT. bash replaces EXIT traps rather than chaining them, so
# the scratch-cleanup trap set during setup was silently discarded when this
# line ran and every run leaked a /tmp/worklog-e2e-* tree. Both cleanups live
# in one function instead.
e2e_cleanup() {
  rm -f "$out_file"
  if [[ -n "${E2E_SCRATCH:-}" ]]; then
    if [[ -n "${E2E_KEEP:-}" ]]; then
      echo "e2e scratch kept: $E2E_SCRATCH" >&2
    else
      rm -rf "$E2E_SCRATCH"
    fi
  fi
}
trap e2e_cleanup EXIT

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
# `command -v a b c` prints only what it finds and exits 0 if ANY one exists,
# so the multi-arg form passed this preflight with ripgrep absent -- a check
# named for six tools that could only ever fail if all six were missing.
# Verified 2026-09-03: `command -v bash python3 perl git rg jq` returned 0 on a
# box with no rg binary. Loop and name the gap instead.
run "preflight: bash + python3 + perl + git + ripgrep + jq present" bash -c '
  missing=""
  for t in bash python3 perl git rg jq; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  if [ -n "$missing" ]; then
    echo "e2e preflight: missing required tools:$missing" >&2
    exit 1
  fi'

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
# install-hooks has two correct outcomes and which one you get depends on the
# machine, not the code: with no outer core.hooksPath it sets one, and with a
# platform-owned outer path already in force it chains symlinks into
# .git/hooks instead. This box carries a SYSTEM-level core.hooksPath
# (/resources/githooks, a gitleaks pre-commit), which every repo inherits, so
# it always chains here. Asserting only the first outcome made this step pass
# or fail on where it ran. Assert the EFFECT both paths must produce -- the
# worklog hooks are reachable -- and accept either mechanism.
if grep -q "core.hooksPath" "$out_file"; then
  assert_contains "core.hooksPath"
else
  assert_contains "chained"
fi

run "worklog hooks are reachable by git" bash -c '
  hp="$(git config --get core.hooksPath || true)"
  if [[ "$hp" == "bin/git-hooks" ]]; then
    exit 0                      # hooksPath mechanism
  fi
  # chained mechanism: .git/hooks entries point at bin/git-hooks/
  for h in pre-commit commit-msg post-commit; do
    [[ -e ".git/hooks/$h" ]] || { echo "missing .git/hooks/$h" >&2; exit 1; }
    readlink ".git/hooks/$h" | grep -q "bin/git-hooks/$h" || {
      echo ".git/hooks/$h does not point at bin/git-hooks/$h" >&2; exit 1; }
  done'

# --- 9. pre-commit hook refuses bin/ inside a data repo ------------------
# This step used to stage bin/checkpoint.sh and require the hook to PASS,
# which was right when bin/ lived in the data repo. The hook has since been
# given the opposite job -- it refuses any staged bin/ path, because the SoT
# moved to the dotfiles skill and a data repo carries only the tombstone. The
# suite still asserted the old contract, so the two could not both be
# satisfied and the step was unpassable by construction, not by environment.
# Assert what the hook is now for.
echo "" >> bin/checkpoint.sh
git add bin/checkpoint.sh
if bin/git-hooks/pre-commit >"$out_file" 2>&1; then
  step="pre-commit should REFUSE a staged bin/ path in a data repo"
  fail
fi
assert_contains "REFUSING"
assert_contains "bin/checkpoint.sh"
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
# Build the token at RUNTIME, never as a literal. This line used to carry a
# real-looking ghp_ string; a redaction pass replaced it with the placeholder
# "<REDACTED:SECRET>", which matches nothing in pre-commit-scan.sh's
# qr/ghp_[A-Za-z0-9]{20,}/ -- so the fixture verifying that the secret scanner
# BLOCKS GitHub PATs could no longer produce one, and the step asserted a
# block that could never happen. A security check that cannot fail.
# Assembling it from parts keeps the source scanner-clean (bare "ghp_" is
# below the 20-char threshold) while the file on disk gets a matching token.
SEEDED_PAT="ghp_$(printf 'A%.0s' $(seq 24))"
echo "leaked $SEEDED_PAT token" > "$NS/seed-token-test.md"
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
# Use seed-impl + seed-blocked: both are still ACTIVE here. seed-design is
# not -- step 5 archives it, and batching it asked checkpoint-batch for "no
# active task file for slug 'seed-design'". The comment said "the existing
# seed-impl + seed-design tasks", which was true when written and stopped
# being true one step earlier. seed-blocked's next_action must start with
# "Waiting on": it is status: blocked, and the FSM contract lints that.
echo '[{"slug":"seed-impl","next":"e2e batch test"},{"slug":"seed-blocked","next":"Waiting on e2e batch test 2"}]' \
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
# checkpoint.sh now prints an ABSOLUTE, quoted path to archive.sh, so the old
# literal "bin/archive.sh seed-impl --reason=" no longer appears. Assert the
# parts that carry the meaning -- the tool and the required flag -- rather
# than a prefix that encodes where the caller happened to be.
assert_contains "archive.sh"
assert_contains "seed-impl --reason="

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
