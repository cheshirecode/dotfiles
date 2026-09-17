#!/usr/bin/env bash
# The machine-local credential reader must pick the RIGHT key and the RIGHT
# occurrence, and bin/env-secret.sh must agree with the copy inlined in
# .envrc. Every case here is a way a near-miss reader returns a confident
# wrong value instead of failing.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/env-secret.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

# --- the file under test ----------------------------------------------------
F="$TMP/.env.secrets"
cat > "$F" <<'EOF'
# a comment
GH_TOKEN_CHESHIRECODE=first-value
GH_TOKEN_CHESHIRECODE=second-value
QUOTED="quoted-value"
SQUOTED='squoted-value'
  INDENTED=indented-value
EMPTY=
NOTE=documentation mentioning MIDLINE_KEY=not-a-real-assignment
MIDLINE_KEY=real-value
EOF
printf 'CRLF_KEY=crlf-value\r\n' >> "$F"
chmod 600 "$F"

# --- extract the inlined copy from .envrc so both are exercised -------------
sed -n '/^secret_get() {/,/^}/p' "$REPO/.envrc" > "$TMP/inlined.sh"
if [ ! -s "$TMP/inlined.sh" ]; then
  note "could not extract secret_get() from .envrc"
  echo "fails=$fails"; exit 1
fi

# Two readers, one contract. `envrc` runs the extracted function; `script`
# runs bin/env-secret.sh. Both are pointed at the same file.
read_via_script() { ENV_SECRETS_FILE="$F" HOME="$TMP" bash "$REPO/bin/env-secret.sh" "$1" 2>/dev/null; }
read_via_envrc()  {
  ENV_SECRETS_FILE="$F" HOME="$TMP" bash -c \
    'source "$1"; secret_get "$2"' _ "$TMP/inlined.sh" "$1" 2>/dev/null
}

# Show invisible bytes. A stray CR or trailing space otherwise prints a
# mismatch whose two sides look identical, which reads like a passing test.
vis() { printf '%s' "$1" | od -c | sed -n '1p' | cut -c9-; }

check() { # check <key> <want> <label>
  local key="$1" want="$2" label="$3" got
  for impl in script envrc; do
    got="$(read_via_"$impl" "$key")"
    if [ "$got" != "$want" ]; then
      note "$label [$impl]: got '$got', want '$want'"
      echo "      bytes got:  $(vis "$got")"
      echo "      bytes want: $(vis "$want")"
    fi
  done
}

check GH_TOKEN_CHESHIRECODE first-value "takes the FIRST assignment, not the last"
check QUOTED   quoted-value    "strips double quotes"
check SQUOTED  squoted-value   "strips single quotes"
check INDENTED indented-value  "tolerates leading whitespace"
check CRLF_KEY crlf-value      "strips the trailing CR of a CRLF file"

# Only a line-start assignment counts. Without the `^` anchor the NOTE line
# above matches first and hands back "not-a-real-assignment". This is the
# assertion that makes the anchor load-bearing; the `=` alone does not.
check MIDLINE_KEY real-value "ignores a key name appearing mid-line"

# A prefix must not satisfy a shorter key. This is the assertion that catches
# an unanchored or unterminated pattern, which would hand back the
# cheshirecode token to anything asking for a bare GH_TOKEN.
for impl in script envrc; do
  got="$(read_via_"$impl" GH_TOKEN)"
  [ -z "$got" ] || note "GH_TOKEN matched the GH_TOKEN_CHESHIRECODE line [$impl]: got '$got'"
done

# An empty key and an absent key are both "no value", and both must be rc 1 —
# never rc 0 with an empty string, which a caller reads as success.
for key in EMPTY ABSENT_KEY; do
  for impl in script envrc; do
    if read_via_"$impl" "$key" >/dev/null 2>&1; then
      note "$key returned rc 0 [$impl]; want rc 1"
    fi
  done
done

# A loose mode must be reported, not silently used.
chmod 644 "$F"
warn="$(ENV_SECRETS_FILE="$F" HOME="$TMP" bash "$REPO/bin/env-secret.sh" QUOTED 2>&1 >/dev/null)"
printf '%s' "$warn" | grep -q 'mode 644' ||
  note "reading a 0644 credential file printed no mode warning"
chmod 600 "$F"

# An absent file is rc 1 with a message, not a crash and not silence.
out="$(ENV_SECRETS_FILE="$TMP/nope" HOME="$TMP/nope-home" bash "$REPO/bin/env-secret.sh" QUOTED 2>&1)"
rc=$?
[ "$rc" -eq 1 ] || note "absent file gave rc $rc, want 1"
printf '%s' "$out" | grep -q 'no readable' || note "absent file printed no explanation"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "ok: both readers agree on key selection, quoting, CRLF, rc and mode warning"
