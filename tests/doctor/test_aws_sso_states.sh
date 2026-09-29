#!/usr/bin/env bash
# Three different things break AWS SSO here and all three present to the user as
# "SSO is broken". Doctor must tell them apart, because the remedies differ:
#   config reverted      -> run restore-home-links.sh   (the image replaced it)
#   cache on the overlay -> relink it                   (a restart will delete it)
#   token not refreshable-> the layout is legacy        (expect a login each time)
#   nothing cached       -> just log in                 (not a failure)
#
# Each case below reproduces a failure actually observed 2026-09-25..28.
# No AWS and no network.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
DOCTOR="$REPO/bin/doctor.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/awsstates.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

CANON="$TMP/canon"
printf '[sso-session s]\nx=1\n\n[profile default]\nsso_session = s\n' > "$CANON"

# Only the aws-sso section, so an unrelated doctor failure cannot mask or fake
# a verdict here.
section() { # section <home> <canon> <persist>
  HOME="$1" AWS_CANON="$2" AWS_SSO_CACHE="$3" bash "$DOCTOR" 2>&1 \
    | sed -n '/doctor: aws sso/,/^doctor: /p' > "$TMP/sec"
}
has() { grep -qE "^  $1 .*$2" "$TMP/sec"; }

# 1. The config revert: image copy restored, sso-session block gone. FAIL, and
#    it must name the remedy — a bare "differs" sends the reader to diff files.
H="$TMP/h1"; mkdir -p "$H/.aws"
printf '[profile default]\nsso_start_url = https://example.invalid/start\n' > "$H/.aws/config"
section "$H" "$CANON" "$TMP/p1"
has FAIL 'sso-session' || note "a reverted config was not reported FAIL"
grep -q 'restore-home-links' "$TMP/sec" || note "the revert verdict does not name the remedy"

# 2. Cache is a real directory on the overlay: the login will not survive.
H2="$TMP/h2"; mkdir -p "$H2/.aws/sso/cache"; cp "$CANON" "$H2/.aws/config"
section "$H2" "$CANON" "$TMP/p2"
has WARN 'real directory on the overlay' || note "an overlay cache dir was not flagged"
has OK 'config matches' || note "a healthy config was not reported OK alongside the cache warning"

# 3. Token present but no refreshToken — the legacy layout, a login every time.
H3="$TMP/h3"; P3="$TMP/p3"; mkdir -p "$P3" "$H3/.aws/sso"
cp "$CANON" "$H3/.aws/config"; ln -s "$P3" "$H3/.aws/sso/cache"
printf '{"accessToken":"x","expiresAt":"2030-01-01T00:00:00Z"}' > "$P3/t.json"
section "$H3" "$CANON" "$P3"
has WARN 'no refreshToken' || note "a non-refreshable token was not flagged"
has OK 'linked to the persistent volume' || note "a correctly linked cache was not reported OK"

# 3b. EXPIRED but carrying a refreshToken. This is the false green that shipped:
#     doctor read the refreshToken KEY and reported "present and refreshable"
#     while every aws call returned 255 with "Token has expired and refresh
#     failed". A refreshToken proves the sso-session layout is in use; it does
#     not prove the token still works, because refresh is bounded by the
#     Identity Center session duration. Measured 2026-09-29: refresh ran
#     silently for ~11.6h after login, then stopped.
printf '{"accessToken":"x","refreshToken":"y","expiresAt":"2000-01-01T00:00:00Z"}' > "$P3/t.json"
section "$H3" "$CANON" "$P3"
has FAIL 'EXPIRED' || note "an expired token with a refreshToken was not reported FAIL"
grep -q 'aws sso login' "$TMP/sec" || note "the expired verdict does not name the remedy"
has OK 'refreshable' && note "an expired token was still reported refreshable"

# 4. A refreshable token is OK, so the WARN above is not simply always-on.
printf '{"accessToken":"x","refreshToken":"y","expiresAt":"2030-01-01T00:00:00Z"}' > "$P3/t.json"
section "$H3" "$CANON" "$P3"
has OK 'refreshable' || note "a refreshable token was not reported OK — the check is stuck on WARN"

# 5. No canonical copy: ABSENT, never a silent OK. Without this, a machine with
#    no canonical file reports healthy while drift is undetectable.
H4="$TMP/h4"; mkdir -p "$H4/.aws"; cp "$CANON" "$H4/.aws/config"
section "$H4" "$TMP/nope" "$TMP/p4"
has ABSENT 'canonical AWS config' || note "a missing canonical copy did not report ABSENT"

# 6. No AWS at all is ABSENT, not FAIL — plenty of machines have none.
H5="$TMP/h5"; mkdir -p "$H5"
section "$H5" "$CANON" "$TMP/p5"
has ABSENT 'not present' || note "a machine with no AWS config was not reported ABSENT"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: doctor separates config revert, overlay cache, non-refreshable token and absent AWS"
