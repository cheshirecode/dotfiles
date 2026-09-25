#!/usr/bin/env bash
# ~/.aws/config is root-owned and ships in the image, so a workspace restart
# REPLACES it with an older copy rather than deleting it. That is a different
# shape from the overlay wipe: the file still exists, still parses, and its
# mtime moves BACKWARDS, so every "does $HOME persist?" check that looks at old
# timestamps reports healthy while the edit is gone.
#
# Measured 2026-09-25: an sso-session migration applied the day before was gone
# after a restart and the symptom read as "SSO refresh is broken".
#
# No AWS and no network here: this pins the restore logic only.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
# NOT "awsrestore": the temp path is printed in this script's own output,
# and a bare grep for "aws" then matches the directory name on every line.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfgrestore.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

CANON="$TMP/canon"
printf '[sso-session s]\nsso_start_url = https://example.invalid/start\n\n[profile default]\nsso_session = s\n' > "$CANON"

run() { # run <home> <canon>
  HOME="$1" AWS_CANON="$2" ENV_SECRETS=/nonexistent VAULT_STAMP="$TMP/stamp" \
    bash "$SCRIPT" >"$TMP/out" 2>&1
}

# 1. A reverted config is restored from the canonical copy.
H="$TMP/h1"; mkdir -p "$H/.aws"
printf '[profile default]\nsso_start_url = https://example.invalid/start\n' > "$H/.aws/config"
run "$H" "$CANON"
cmp -s "$CANON" "$H/.aws/config" || note "a reverted ~/.aws/config was not restored"
grep -q 'restored ~/.aws/config' "$TMP/out" || note "the restore was silent; it must say what it changed"

# 2. Idempotent: an already-correct config produces no output and no rewrite.
before="$(stat -c %Y "$H/.aws/config")"
run "$H" "$CANON"
grep -q 'restored ~/.aws/config' "$TMP/out" && note "a no-op run still reported a restore"
[ "$(stat -c %Y "$H/.aws/config")" = "$before" ] || note "a no-op run rewrote the file"

# 3. No canonical copy: silent, and it must NOT delete or truncate the live one.
H2="$TMP/h2"; mkdir -p "$H2/.aws"; printf 'keepme\n' > "$H2/.aws/config"
run "$H2" "$TMP/does-not-exist"
grep -q 'restored ~/.aws/config' "$TMP/out" && note "an absent canonical copy reported a restore"
grep -q 'keepme' "$H2/.aws/config" || note "an absent canonical copy damaged the live config"

# 4. The canonical path must be overridable, or the test above proves nothing
#    about the shipped default and the script is untestable off this machine.
grep -q 'AWS_CANON:-' "$SCRIPT" || note "the canonical AWS path is not overridable via AWS_CANON"

# 5. No site value may be embedded here. The content lives on the persistent
#    volume precisely because it carries account ids, role names and a start url.
grep -qE 'awsapps\.com|[0-9]{12}' "$SCRIPT" && note "an AWS account id or start url leaked into the repo"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: ~/.aws/config is restored from the persistent copy, idempotently, with no site value in the repo"
