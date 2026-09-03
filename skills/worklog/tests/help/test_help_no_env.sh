#!/usr/bin/env bash
# Public help paths should not require a worklog checkout or imported .envrc.

set -euo pipefail

# Pinned to the tree under test, not `${WORKLOG_BIN:-...}`. A developer
# profile exports WORKLOG_BIN at the *installed* skill, which is a different
# checkout; honouring it makes this fixture grade the installed helpers
# instead of the ones sitting next to it, so a fix in the working tree can
# read green against unfixed code. tests/run.sh unsets the variable, and
# deriving it here keeps the fixture honest when run by hand too.
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"
SCRATCH="$(mktemp -d -t worklog-help-no-env-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

scripts=(
  archive
  audit
  checkpoint
  context
  lint
  project
  scrape-slack
  search
  status
)

for script in "${scripts[@]}"; do
  (
    cd "$SCRATCH"
    unset WORKLOG_REPO WORKLOG_LDAP WORKLOG_NS
    "$WORKLOG_BIN/$script.sh" --help >/dev/null
  ) || {
    echo "help-no-env: $script --help required repo/env" >&2
    exit 1
  }
done

echo "help-no-env: ok"
