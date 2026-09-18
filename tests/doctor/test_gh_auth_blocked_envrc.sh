#!/usr/bin/env bash
# The gh auth probe must report UNKNOWN when direnv refuses to load the tree's
# .envrc. The token that tree would use was never resolved, so the probe has
# no answer; reporting FAIL (rejected credential) or ABSENT (no login) would
# collapse "could not tell" into a verdict.
#
# The repo itself no longer carries a root .envrc, so the CI image cannot
# reach this branch by accident. Build the fixture: a copy of doctor.sh whose
# REPO_ROOT holds an .envrc that has never been approved.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${DOCTOR_BIN:-$ROOT/bin/doctor.sh}"

if [ ! -x "$DOCTOR" ]; then
  echo "test_gh_auth_blocked_envrc NOT RUN — nothing asserted; $DOCTOR missing or not executable." >&2
  exit 2
fi
for tool in direnv gh; do
  if ! command -v "$tool" >/dev/null; then
    echo "test_gh_auth_blocked_envrc NOT RUN — $tool is required to reach the probe." >&2
    exit 2
  fi
done

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

# doctor.sh derives REPO_ROOT from its own location, so the copy lives in
# $T/repo/bin and the fixture .envrc in $T/repo. A fresh path is unapproved,
# which is the blocked state. Do NOT `direnv deny` it: direnv 2.37 treats an
# explicitly denied .envrc as "skip", runs the command with the caller's env
# and prints no error, so the fixture would measure the caller's token.
mkdir -p "$T/repo/bin"
cp "$DOCTOR" "$T/repo/bin/doctor.sh"
printf 'export PROBE=1\n' > "$T/repo/.envrc"

# Scrub the caller's direnv state and tokens. `direnv exec` first reverts the
# diff recorded in DIRENV_DIFF, which puts a login-shell token back even after
# `env -u`; the probe must see the fixture, not the developer's shell.
# Only the gh auth section matters; the other probes see an empty repo.
out="$(env -u DIRENV_DIFF -u DIRENV_DIR -u DIRENV_WATCHES -u DIRENV_FILE -u GH_TOKEN -u GITHUB_TOKEN \
  bash "$T/repo/bin/doctor.sh" 2>&1 | sed -n '/^doctor: gh auth/,/^doctor: /p')"

pass=0; fail=0
if printf '%s' "$out" | grep -q "UNKNOWN gh auth unverifiable: .envrc not approved for $T/repo"; then
  pass=$((pass+1)); echo "  PASS  blocked .envrc reports UNKNOWN"
else
  fail=$((fail+1)); echo "  FAIL  blocked .envrc did not report UNKNOWN:"; printf '%s\n' "$out" | sed 's/^/        /'
fi
if printf '%s' "$out" | grep -Eq '^\s+(FAIL|ABSENT|OK)\s+gh '; then
  fail=$((fail+1)); echo "  FAIL  probe also gave a verdict it could not know:"; printf '%s\n' "$out" | grep -E '^\s+(FAIL|ABSENT|OK)\s+gh ' | sed 's/^/        /'
else
  pass=$((pass+1)); echo "  PASS  no FAIL/ABSENT/OK verdict alongside UNKNOWN"
fi

echo "test_gh_auth_blocked_envrc: $pass pass, $fail fail"
[ "$fail" -eq 0 ]
