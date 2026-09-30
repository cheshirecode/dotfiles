#!/usr/bin/env bash
# The SSO token cache is DESTROYED by a workspace restart — ~/.aws/sso/ does not
# exist afterwards. That is the opposite failure from ~/.aws/config, which is
# root-owned and gets REPLACED with the image copy. Both look like a broken
# credential: the missing cache reports "Token for super does not exist", which
# reads as an expiry or a failed refresh and is neither.
#
# Measured 2026-09-28: a token that had refreshed silently for two days was gone
# with its directory, purely because the workspace restarted.
#
# No AWS and no network here.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ssopersist.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

run() { # run <home> <cache>
  HOME="$1" AWS_SSO_CACHE="$2" AWS_CANON=/nonexistent \
    ENV_SECRETS=/nonexistent VAULT_STAMP="$TMP/stamp" \
    bash "$SCRIPT" >"$TMP/out" 2>&1
}

# 1. Fresh home, no cache dir at all — the post-restart state.
H="$TMP/h1"; P="$TMP/p1"; mkdir -p "$H/.aws"
run "$H" "$P"
[ -L "$H/.aws/sso/cache" ] || note "a missing cache dir was not replaced with a link"
[ "$(readlink "$H/.aws/sso/cache")" = "$P" ] || note "the link does not point at the persistent path"

# 2. A REAL directory already there — the aws CLI recreates it on any failed
#    call, so this is the common case, not the rare one. `ln -sfn TARGET DIR`
#    against an existing directory puts the link INSIDE it and still reports
#    success: you get .../cache/<name> and a cache still on the overlay.
H2="$TMP/h2"; P2="$TMP/p2"; mkdir -p "$H2/.aws/sso/cache"
printf '{"accessToken":"x"}\n' > "$H2/.aws/sso/cache/tok.json"
run "$H2" "$P2"
[ -L "$H2/.aws/sso/cache" ] || note "an existing real cache dir was not converted to a link"
[ -e "$P2/tok.json" ] || note "an existing token was not migrated — that is a login the operator must repeat"
[ -e "$H2/.aws/sso/cache/$(basename "$P2")" ] && note "the link landed INSIDE the directory (ln -sfn trap)"

# 3. Idempotent: a second run must not re-announce or re-link.
run "$H2" "$P2"
grep -q 'SSO tokens now survive' "$TMP/out" && note "a no-op run re-announced the link"

# 4. Opt-out must be honoured, and must not touch the home dir.
H3="$TMP/h3"; mkdir -p "$H3/.aws"
HOME="$H3" AWS_SSO_CACHE='' AWS_CANON=/nonexistent ENV_SECRETS=/nonexistent \
  VAULT_STAMP="$TMP/stamp" bash "$SCRIPT" >"$TMP/out" 2>&1
grep -q 'SSO tokens now survive' "$TMP/out" && note "an empty AWS_SSO_CACHE still linked the cache"
[ -e "$H3/.aws/sso/cache" ] && note "an empty AWS_SSO_CACHE still created the cache path"

# 5. The persistent dir must not be world-readable: it holds live tokens.
mode=$(stat -c '%a' "$P" 2>/dev/null)
case "$mode" in 700|2700) ;; *) note "persistent cache dir is mode $mode, want 700" ;; esac

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: SSO cache is linked to the persistent volume, migrates an existing dir, idempotent, opt-out honoured, 0700"
