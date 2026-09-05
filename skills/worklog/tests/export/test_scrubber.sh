#!/usr/bin/env bash
# test_scrubber.sh — clean-content scrubber regression test.
#
# Pipes tests/export/clean_corpus.txt through the SECRET-only subset of the
# perl scrub() in bin/export-setup.sh and asserts byte-identity. A diff means
# a secret regex is over-eager — anchor the match (require boundary like ^,
# whitespace, =) or narrow the character class.
#
# Org/domain/repo/ldap/path generalizations are NOT tested here — those subs
# are intentional and would always fire. Scope is strictly secret detection
# regression on realistic, secret-free content.
#
# Lifted from the audit-prompt § "Test the scrubber on clean content."
#
# Usage: tests/export/test_scrubber.sh
# Exit:  0 byte-identical, 1 secret regex fired on clean content, 2 invocation.

set -euo pipefail

# Resolve sibling bin/ (relocated from data repo to skill).
# Pinned to the tree under test, not `${WORKLOG_BIN:-...}`. A developer
# profile exports WORKLOG_BIN at the *installed* skill, which is a different
# checkout; honouring it makes this fixture grade the installed helpers
# instead of the ones sitting next to it, so a fix in the working tree can
# read green against unfixed code. tests/run.sh unsets the variable, and
# deriving it here keeps the fixture honest when run by hand too.
WORKLOG_BIN="$(cd "$(dirname "$0")/../../bin" && pwd)"

cd "$(dirname "$0")/../.."

CORPUS="tests/export/clean_corpus.txt"
[[ -f "$CORPUS" ]] || { echo "missing $CORPUS" >&2; exit 2; }

# Extract ONLY the secret patterns (the <REDACTED:SECRET> lines) from the
# real scrub() in bin/export-setup.sh — a hand-copied mirror of the list
# already drifted once (2026-09-05: jwt/pem landed in bin but not here).
# Generalization subs (org/ldap/path) are excluded by the grep, so the
# clean-corpus byte-identity assertion still holds.
SCRUBBED="$(mktemp)"
PLANTED_OUT="$(mktemp)"
trap 'rm -f "$SCRUBBED" "$PLANTED_OUT"' EXIT
SECRET_PROG="$(sed -n '/^scrub() {/,/^}/p' "$WORKLOG_BIN/export-setup.sh" | grep 'REDACTED:SECRET')"
[[ -n "$SECRET_PROG" ]] || { echo "could not extract secret patterns from export-setup.sh" >&2; exit 2; }
perl -pe "$SECRET_PROG" <"$CORPUS" >"$SCRUBBED"

# Under-match side: every planted secret shape must be redacted.
PLANTED='sk-aaaaaaaaaaaaaaaaaaaaaaaa
ghp_bbbbbbbbbbbbbbbbbbbbbbbb
github_pat_cccccccccccccccccccc
xoxb-1234567890-abcdef
AIzaDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
AKIAEEEEEEEEEEEEEEEE
glpat-ffffffffffffffffffff
ATATT3gggggggggggggggg
ddpat_hhhhhhhhhhhhhhhhhhhh
npm_iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii
eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dozjgNryP4J3jVmNHl0w5N
-----BEGIN RSA PRIVATE KEY-----
MIIEfakefakefake
-----END RSA PRIVATE KEY-----'
printf '%s\n' "$PLANTED" | perl -pe "$SECRET_PROG" >"$PLANTED_OUT"
if grep -qE 'sk-a|ghp_b|github_pat_c|xoxb-1|AIzaD|AKIAE|glpat-f|ATATT3g|ddpat_h|npm_i|eyJ|BEGIN RSA|MIIEfake' "$PLANTED_OUT"; then
  echo "scrubber: REGRESSION — a planted secret shape survived scrub():" >&2
  grep -E 'sk-a|ghp_b|github_pat_c|xoxb-1|AIzaD|AKIAE|glpat-f|ATATT3g|ddpat_h|npm_i|eyJ|BEGIN RSA|MIIEfake' "$PLANTED_OUT" >&2
  exit 1
fi
echo "scrubber: all planted secret shapes redacted ✓"

if diff -u "$CORPUS" "$SCRUBBED"; then
  echo "scrubber: clean corpus survived untouched ✓"
  exit 0
else
  echo
  echo "scrubber: REGRESSION — secret regex fired on clean content." >&2
  echo "Anchor the offending pattern (require ^, whitespace, or = boundary)" >&2
  echo "or narrow the character class. See audit-prompt § 3." >&2
  exit 1
fi
