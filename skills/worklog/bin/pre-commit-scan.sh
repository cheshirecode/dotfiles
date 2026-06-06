#!/usr/bin/env bash
# pre-commit-scan.sh — secret-leak guard for staged worklog edits.
#
# Reads the staged additions (`git diff --cached`) and greps for typed-prefix
# secret tokens. Reuses the regex set from bin/export-setup.sh::scrub() so the
# commit-side and export-side scrubbers stay in lockstep — see docs/protocol.md
# § Drift surfaces (D5).
#
# Scope decision (Karpathy 2: simplicity-first): secrets only, not PII.
# Worklog task bodies routinely contain @cheshirecode.ai email addresses by design
# (collaborator references, PR authors). A PII scanner that flagged those
# every commit would be pure noise; export-side already maps the org domain
# to users.noreply.github.com for outside-of-org sharing. If targeted PII surfaces
# (phone numbers, customer email) ever materialize as a real failure mode,
# extend then — don't speculate now.
#
# Usage:
#   bin/pre-commit-scan.sh                       # advisory: warn + exit 0
#   WORKLOG_STRICT_SCAN=1 bin/pre-commit-scan.sh # block: warn + exit 1
#
# Bypass: `WORKLOG_NO_SCAN=1 git commit ...` (parity with WORKLOG_NO_HOOK).
#
# Granularity: only NEW added lines are scanned (`+` lines from unified diff,
# excluding the `+++` file header). Pre-existing matches in archived content
# are grandfathered.

set -euo pipefail

[[ -n "${WORKLOG_NO_SCAN:-}" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"

# Pull staged additions: lines starting with a single `+` and not `+++` headers.
ADDED="$(git diff --cached --no-color -U0 -- ':!tests/**' \
  | awk '/^\+\+\+ /{next} /^\+/{print}')"

[[ -z "$ADDED" ]] && exit 0

# Mirror the regex set from bin/export-setup.sh::scrub(). If you change one,
# change both — pre-commit hook D5 advisory catches divergence.
HITS="$(printf '%s\n' "$ADDED" | perl -ne '
  my @pats = (
    [SECRET_OPENAI       => qr/sk-[A-Za-z0-9_-]{20,}/],
    [SECRET_GH_PAT       => qr/ghp_[A-Za-z0-9]{20,}/],
    [SECRET_GH_FINE_PAT  => qr/github_pat_[A-Za-z0-9_]{20,}/],
    [SECRET_SLACK        => qr/xox[abpros]-[A-Za-z0-9-]{10,}/],
    [SECRET_GCP_KEY      => qr/AIza[A-Za-z0-9_-]{35}/],
    [SECRET_AWS_KEY      => qr/AKIA[0-9A-Z]{16}/],
  );
  for my $p (@pats) {
    if (/$p->[1]/) {
      print "$p->[0]: $&\n";
    }
  }
')"

[[ -z "$HITS" ]] && exit 0

echo "pre-commit-scan: typed-prefix secret patterns found in staged additions:" >&2
printf '  %s\n' $HITS >&2
echo "" >&2
echo "  If false positive, redact / move out of the staged content. Bypass:" >&2
echo "    WORKLOG_NO_SCAN=1 git commit ...    # one-shot" >&2
echo "    WORKLOG_STRICT_SCAN=0               # default (advisory)" >&2

if [[ "${WORKLOG_STRICT_SCAN:-0}" == "1" ]]; then
  echo "pre-commit-scan: blocking (WORKLOG_STRICT_SCAN=1)." >&2
  exit 1
fi
exit 0
