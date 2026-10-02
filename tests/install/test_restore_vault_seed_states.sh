#!/usr/bin/env bash
# restore-home-links.sh seeds ~/.vault-token and then checks the token. Three
# outcomes must stay distinct: verified, refused, and unverifiable because no
# address is configured. The third used to print "DOES NOT AUTHENTICATE" for a
# token that was valid, which sends the reader after the wrong fault.
#
# No network: a loopback stub answers lookup-self. env -i, because a
# VAULT_TOKEN_PROD exported in the calling shell would otherwise be found
# ambiently and the secrets file under test would never be read.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vaultseed.XXXXXX")"
SRV_PID=""
trap '[ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

python3 - "$TMP/port" <<'EOF' &
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        ok = self.headers.get("X-Vault-Token") == "good-token"
        body = json.dumps({"data": {"ttl": 2678400}} if ok else {"errors": ["permission denied"]}).encode()
        self.send_response(200 if ok else 403); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port))
s.serve_forever()
EOF
SRV_PID=$!
for _ in $(seq 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
[ -s "$TMP/port" ] || { echo "FAIL: stub vault did not start"; exit 1; }
ADDR="http://127.0.0.1:$(cat "$TMP/port")"

run() {  # <case> <token> <addr or empty> -> output in $TMP/<case>.out
  local h="$TMP/$1"; mkdir -p "$h"
  printf 'VAULT_TOKEN_PROD=%s\n' "$2" > "$h/secrets"
  env -i HOME="$h" PATH=/usr/bin:/bin:/usr/local/bin ENV_SECRETS="$h/secrets" \
    VAULT_STAMP="$h/stamp" AWS_CANON=/nonexistent AWS_SSO_CACHE='' VAULT_PROD_ADDR="$3" \
    bash "$SCRIPT" > "$TMP/$1.out" 2>&1
}

run unset good-token ""
# shellcheck disable=SC2016  # the message names the variable literally
grep -q 'UNVERIFIED: \$VAULT_PROD_ADDR is unset' "$TMP/unset.out" || note "unset address: no UNVERIFIED message"
grep -q 'DOES NOT AUTHENTICATE' "$TMP/unset.out" && note "unset address: still claims the token does not authenticate"
[ -s "$TMP/unset/.vault-token" ] || note "unset address: the token file was not seeded"

run refused bad-token "$ADDR"
grep -q 'DOES NOT AUTHENTICATE' "$TMP/refused.out" || note "refused token: no DOES NOT AUTHENTICATE message"

run verified good-token "$ADDR"
grep -q 'seeded ~/.vault-token from VAULT_TOKEN_PROD (overlay wipe)' "$TMP/verified.out" || note "valid token: no verified-seed message"
grep -qE 'UNVERIFIED|DOES NOT AUTHENTICATE' "$TMP/verified.out" && note "valid token: reported as a failure"

grep -h -e 'good-token' -e 'bad-token' "$TMP"/*.out >/dev/null && note "a token value was printed"

if [ "$fails" -ne 0 ]; then
  for c in unset refused verified; do echo "--- $c ---"; grep -i vault "$TMP/$c.out"; done
  exit 1
fi
echo "ok: seed check separates verified, refused and unverifiable (no address)"
