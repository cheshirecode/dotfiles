# Shared scratch-vault setup for the archive/ fixtures. Sourced, not run —
# the runner globs test_*.sh, so this leading-underscore file is not a fixture.
#
# Isolation follows transcript/test_dump.sh: a bare upstream plus a fresh clone
# under $TMPDIR, with WORKLOG_REPO/WORKLOG_LDAP pinned to it, so nothing here
# can reach the real vault. tests/run.sh already strips BASH_ENV via
# WL_HERMETIC, which is what stops a developer shell's exported WORKLOG_REPO
# from being re-exported over these per-command assignments.

# Pinned, not `${WORKLOG_BIN:-...}`: WL_HERMETIC drops BASH_ENV but does not
# unset an already-exported WORKLOG_BIN, and a developer shell exports one
# pointing at the *installed* skill (~/.claude/skills/worklog/bin). Honouring
# it makes these fixtures assert against whatever is installed rather than the
# archive.sh sitting next to them, which is how a fix in the working tree can
# read green against unfixed code.
WORKLOG_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)"

make_vault() {
  SCRATCH_ROOT="$(mktemp -d -t archive-honesty-XXXXXX)"
  SCRATCH="$SCRATCH_ROOT/repo"
  UPSTREAM="$SCRATCH_ROOT/upstream.git"
  export TMPDIR="$SCRATCH_ROOT/tmp"
  mkdir -p "$TMPDIR"

  git init -q --bare --initial-branch=main "$UPSTREAM"
  git init -q --initial-branch=main "$SCRATCH"
  cd "$SCRATCH"
  export WORKLOG_REPO="$SCRATCH"
  export WORKLOG_LDAP=tester
  export WORKLOG_NO_HOOK=1
  export WORKLOG_SKIP_PROVENANCE=1
  export WORKLOG_NO_RETRO=1
  export WORKLOG_NO_TRANSCRIPT=1
  git config user.email "tester@example.com"
  git config user.name "archive-honesty-test"
  git config commit.gpgsign false
  git remote add origin "$UPSTREAM"
  mkdir -p "people/tester/active" "people/tester/archive" .cache
  touch "people/tester/archive/.gitkeep" .cache/provenance-verified
  git add -A
  git commit -q -m "seed" --no-verify
  git push -q origin HEAD:main
  git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
}

write_task() {
  cat > "$SCRATCH/people/tester/active/$1.md" <<EOF
---
slug: $1
kind: investigation
status: in-progress
project: sample
last_updated: 2026-07-25
next_action: Work on $1
repos: [sample]
---

## Context
Archive-honesty fixture.

## Next
- [ ] Work on $1
EOF
}
