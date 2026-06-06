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
WORKLOG_BIN="${WORKLOG_BIN:-$(cd "$(dirname "$0")/../../bin" && pwd)}"

cd "$(dirname "$0")/../.."

CORPUS="tests/export/clean_corpus.txt"
[[ -f "$CORPUS" ]] || { echo "missing $CORPUS" >&2; exit 2; }

# Mirror ONLY the secret patterns from scrub() in bin/export-setup.sh.
# Keep in sync — if a secret pattern is added there, add it here too.
SCRUBBED="$(mktemp)"
trap 'rm -f "$SCRUBBED"' EXIT
perl -pe '
  s{sk-[A-Za-z0-9_-]{20,}}{<REDACTED:SECRET>}g;
  s{ghp_[A-Za-z0-9]{20,}}{<REDACTED:SECRET>}g;
  s{github_pat_[A-Za-z0-9_]{20,}}{<REDACTED:SECRET>}g;
  s{xox[abpros]-[A-Za-z0-9-]{10,}}{<REDACTED:SECRET>}g;
  s{AIza[A-Za-z0-9_-]{35}}{<REDACTED:SECRET>}g;
  s{AKIA[0-9A-Z]{16}}{<REDACTED:SECRET>}g;
' <"$CORPUS" >"$SCRUBBED"

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
