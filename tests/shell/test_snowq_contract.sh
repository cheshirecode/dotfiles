#!/usr/bin/env bash
# snowq's contract, tested WITHOUT a Snowflake or a Vault: every case here is a
# refusal or an argument decision, which is the part a generic tool can be held
# to anywhere. Anything needing a live warehouse belongs on the machine that has
# one, not in this suite.
#
# The exit codes are the contract. 1 and 2 and 3 are kept apart because "retry",
# "fix your command" and "fix your query" are different responses, and a tool
# that answers all three with one non-zero makes a caller retry a typo.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SNOWQ="$REPO/bin/snowq"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/snowq.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# A bare environment, so a developer's exported config cannot make a refusal
# look like a pass. HOME is set because the script looks there for the helper.
run() { env -i PATH=/usr/bin:/bin HOME="$TMP" "$@" >"$TMP/o" 2>"$TMP/e"; }

rc_is() { # rc_is <want> <label> <env-assignments...> -- <args...>
  local want="$1" label="$2"; shift 2
  run "$@"
  local got=$?
  [ "$got" = "$want" ] || { note "$label: rc $got, want $want"; sed 's/^/      /' "$TMP/e" | head -2; }
}

# Configuration is required and has NO default. A default service name would
# bake one organisation's Vault layout into a generic tool; a default
# interpreter would silently pick some other checkout's virtualenv.
rc_is 2 "no SNOWQ_PYTHON is refused"            bash "$SNOWQ" "select 1"
rc_is 2 "unreadable SNOWQ_PYTHON is refused"    env SNOWQ_PYTHON=/nonexistent/python bash "$SNOWQ" "select 1"
rc_is 2 "no SNOWQ_VAULT_SERVICE is refused"     env SNOWQ_PYTHON=/usr/bin/python3 bash "$SNOWQ" "select 1"

# Usage errors are 2, never the 1 that means a connection failed.
rc_is 2 "no query is refused"                   bash "$SNOWQ"
rc_is 2 "unknown flag is refused"               bash "$SNOWQ" --bogus
rc_is 2 "--help exits 2"                        bash "$SNOWQ" --help
rc_is 2 "unreadable -f file is refused"         env SNOWQ_PYTHON=/usr/bin/python3 SNOWQ_VAULT_SERVICE=svc bash "$SNOWQ" -f "$TMP/nope.sql"

# -f and a positional query together are refused rather than resolved. Silently
# preferring one runs something the caller did not ask for.
printf 'select 1\n' > "$TMP/q.sql"
rc_is 2 "-f plus a query is refused"            env SNOWQ_PYTHON=/usr/bin/python3 SNOWQ_VAULT_SERVICE=svc bash "$SNOWQ" -f "$TMP/q.sql" "select 2"
run env SNOWQ_PYTHON=/usr/bin/python3 SNOWQ_VAULT_SERVICE=svc bash "$SNOWQ" -f "$TMP/q.sql" "select 2"
grep -q 'not both' "$TMP/e" || note "-f plus a query did not explain the conflict"

# An unknown flag must not be swallowed as the query. That defect shipped in a
# sibling tool: an unknown flag became a positional, passed a downstream guard,
# and the failure was reported against the system two layers down.
run bash "$SNOWQ" --json --bogus
grep -q 'unknown option' "$TMP/e" || note "an unknown flag was not named as such"

# The refusals must SAY which knob is missing; "it failed" sends the reader to
# the wrong place. Each message names the variable to set.
run bash "$SNOWQ" "select 1"
grep -q 'SNOWQ_PYTHON' "$TMP/e" || note "the missing-interpreter refusal did not name SNOWQ_PYTHON"
run env SNOWQ_PYTHON=/usr/bin/python3 bash "$SNOWQ" "select 1"
grep -q 'SNOWQ_VAULT_SERVICE' "$TMP/e" || note "the missing-service refusal did not name SNOWQ_VAULT_SERVICE"

# Nothing may reach stdout on a refusal: a caller doing rows=$(snowq ...) must
# get an empty string, not an error message it would go on to parse.
for args in "" "--bogus"; do
  run bash "$SNOWQ" $args
  [ ! -s "$TMP/o" ] || note "a refusal wrote to stdout: $(head -1 "$TMP/o")"
done

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: snowq refuses without config, keeps usage at rc 2, and stays silent on stdout"
