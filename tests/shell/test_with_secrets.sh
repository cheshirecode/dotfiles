#!/usr/bin/env bash
# with-secrets.sh must export the keys it was ASKED for and no others. The
# whole point is scope: a credential reaches one process, so a test that only
# checked "the key arrives" would pass while the file leaked wholesale.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/with-secrets.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

F="$TMP/.env.secrets"
cat > "$F" <<'EOF'
GH_TOKEN_CHESHIRECODE=owner-scoped-token
ANTHROPIC_API_KEY=anthropic-key
OPENROUTER_API_KEY=openrouter-key
UNRELATED_SECRET=must-not-leak
EMPTY_KEY=
EOF
chmod 600 "$F"

W() { ENV_SECRETS_FILE="$F" HOME="$TMP" bash "$REPO/bin/with-secrets.sh" "$@"; }

# 1. A bare key exports under its own name.
got="$(W ANTHROPIC_API_KEY -- sh -c 'printf %s "${ANTHROPIC_API_KEY:-}"' 2>/dev/null)"
[ "$got" = "anthropic-key" ] || note "bare key: got '$got', want 'anthropic-key'"

# 2. ENVVAR:KEY renames. This is how a file keyed by owner feeds a tool that
#    wants the plain name.
got="$(W GH_TOKEN:GH_TOKEN_CHESHIRECODE -- sh -c 'printf %s "${GH_TOKEN:-}"' 2>/dev/null)"
[ "$got" = "owner-scoped-token" ] || note "renamed key: got '$got', want 'owner-scoped-token'"

# 3. THE assertion: a key that was not named must not reach the child, even
#    though it sits in the same file.
got="$(W ANTHROPIC_API_KEY -- sh -c 'printf %s "${UNRELATED_SECRET:-}"' 2>/dev/null)"
[ -z "$got" ] || note "an unnamed key leaked into the child: '$got'"

# 4. Several keys at once.
got="$(W ANTHROPIC_API_KEY OPENROUTER_API_KEY -- sh -c 'printf "%s,%s" "${ANTHROPIC_API_KEY:-}" "${OPENROUTER_API_KEY:-}"' 2>/dev/null)"
[ "$got" = "anthropic-key,openrouter-key" ] || note "multiple keys: got '$got'"

# 5. An absent or empty key warns on stderr and still runs the command. A
#    CLI with its own OAuth session works without the key; a silent skip
#    would make an unset credential look like a set one.
err="$(W MISSING_KEY -- true 2>&1 >/dev/null)"
printf '%s' "$err" | grep -q 'MISSING_KEY' || note "absent key printed no warning"
W MISSING_KEY -- true >/dev/null 2>&1 || note "absent key stopped the command from running"
err="$(W EMPTY_KEY -- true 2>&1 >/dev/null)"
printf '%s' "$err" | grep -q 'EMPTY_KEY' || note "an empty value printed no warning"

# 6. The command's own exit status must pass through, or a caller cannot tell
#    a failed command from a failed wrapper. Measured: removing the bare
#    `exec` does NOT break this, because `env` is then the last command and
#    its status is the script's. `exec` earns its place by replacing the
#    process, so no extra shell sits between the caller and signals.
W ANTHROPIC_API_KEY -- sh -c 'exit 7' >/dev/null 2>&1
rc=$?
[ "$rc" -eq 7 ] || note "child exit status not propagated: got $rc, want 7"

# 7. Misuse is rc 2, not a silent no-op run.
W -- true >/dev/null 2>&1; [ $? -eq 2 ] || note "no keys given: want rc 2"
W ANTHROPIC_API_KEY >/dev/null 2>&1; [ $? -eq 2 ] || note "no command given: want rc 2"

# 8. The value must not appear on stdout. The wrapper prints diagnostics, and
#    a credential echoed into a log is the failure this file exists to avoid.
out="$(W ANTHROPIC_API_KEY -- true 2>&1)"
printf '%s' "$out" | grep -q 'anthropic-key' && note "the wrapper printed the secret value"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: named keys exported, unnamed keys withheld, status and warnings correct"
