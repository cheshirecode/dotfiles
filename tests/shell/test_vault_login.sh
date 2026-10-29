#!/usr/bin/env bash
# bin/vault-login.sh: headless OIDC login with every endpoint injected. A stub
# vault CLI runs a real callback listener and writes the token where the real
# CLI's token helper does ($HOME/.vault-token); a loopback stub answers the
# Vault API. No network, no real Vault, no site names.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/vault-login.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vaultlogin.XXXXXX")"
API_PID=""
cleanup() {
  [ -n "$API_PID" ] && kill "$API_PID" 2>/dev/null
  for p in "$TMP"/state/*/pid; do [ -s "$p" ] && kill "$(cat "$p")" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# Stub Vault API: tokens named in $TMP/valid authenticate; renew grants 32 days.
touch "$TMP/valid"
python3 - "$TMP/api_port" "$TMP/valid" <<'EOF' &
import http.server, json, sys
valid_file = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, body, code=200):
        self.send_response(code); self.end_headers(); self.wfile.write(json.dumps(body).encode())
    def ok(self):
        return self.headers.get("X-Vault-Token", "") in open(valid_file).read().split()
    def do_GET(self):
        self.reply({"data": {"ttl": 86400}} if self.ok() else {"errors": ["denied"]}, 200 if self.ok() else 403)
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        self.reply({"auth": {"lease_duration": 2764800}} if self.ok() else {"errors": ["denied"]}, 200 if self.ok() else 403)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_port)); s.serve_forever()
EOF
API_PID=$!
for _ in $(seq 50); do [ -s "$TMP/api_port" ] && break; sleep 0.1; done
[ -s "$TMP/api_port" ] || { echo "FAIL: stub Vault API did not start"; exit 1; }
API="http://127.0.0.1:$(cat "$TMP/api_port")"

# Stub vault CLI: `login ... port=N` listens on N, prints an authorize URL with a
# fixed state, and on the callback writes the token like the real token helper.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/vault" <<EOF
#!/usr/bin/env python3
import http.server, json, os, sys, urllib.parse as u
port = int(next(a.split("=",1)[1] for a in sys.argv if a.startswith("port=")))
tok = "tok-" + os.path.basename(os.environ["VAULT_ADDR"].rstrip("/")) + "-" + open("$TMP/next").read().strip()
sys.stderr.write("Complete the login via your OIDC provider. Launching browser to:\\n\\n    "
  "https://idp.example.invalid/authorize?client_id=x&state=st_TEST\\n\\n")
sys.stderr.flush()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        q = dict(u.parse_qsl(u.urlsplit(self.path).query))
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
        if q.get("state") == "st_TEST" and q.get("code"):
            open(os.path.join(os.environ["HOME"], ".vault-token"), "w").write(tok)
            print(json.dumps({"auth": {"client_token": tok, "lease_duration": 86400}})); sys.stdout.flush()
            os._exit(0)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
EOF
chmod +x "$TMP/bin/vault"

H="$TMP/home"; mkdir -p "$H"
SEC="$TMP/secrets"
printf 'OTHER_KEY=keep-me\nVAULT_TOKEN_PROD=tok-old-prod\nVAULT_TOKEN_STAGING=tok-old-staging\n' > "$SEC"; chmod 600 "$SEC"
echo tok-old-prod >> "$TMP/valid"          # the old prod token still works; the old staging one does not
printf 'tok-old-prod' > "$H/.vault-token"
PORT="$(free_port)"

vl() {  # run the helper with everything injected
  env -i HOME="$H" PATH="$TMP/bin:/usr/bin:/bin:/usr/local/bin" ENV_SECRETS="$SEC" \
    VAULT_LOGIN_PORT="$PORT" VAULT_LOGIN_STATE="$TMP/state" VAULT_BIN="$TMP/bin/vault" \
    VAULT_PROD_ADDR="$API/prod" VAULT_STAGING_ADDR="$API/staging" "$@"
}
vl_noaddr() {
  env -i HOME="$H" PATH="$TMP/bin:/usr/bin:/bin" ENV_SECRETS="$SEC" VAULT_LOGIN_STATE="$TMP/state" \
    VAULT_BIN="$TMP/bin/vault" bash "$SCRIPT" "$@"
}
cb="http://localhost:$PORT/oidc/callback?code=c0de&state=st_TEST"

# 1. No address injected: refuse, and name the variable.
out="$(vl_noaddr start prod 2>&1)"; rc=$?
[ "$rc" = 2 ] || note "case 1: start with no address exited $rc, want 2"
printf '%s' "$out" | grep -q 'VAULT_PROD_ADDR' || note "case 1: the error does not name VAULT_PROD_ADDR"

# 2. prod login: start prints the URL, a callback with the wrong state is refused.
echo new-prod > "$TMP/next"; echo "tok-prod-new-prod" >> "$TMP/valid"
url="$(vl bash "$SCRIPT" start prod 2>/dev/null)"
printf '%s' "$url" | grep -q '^https://idp.example.invalid/authorize' || note "case 2: start did not print the authorize URL"
before="$(cksum < "$SEC")"
vl bash "$SCRIPT" finish prod "http://localhost:$PORT/oidc/callback?code=c0de&state=st_OTHER" > "$TMP/o2" 2>&1 &&
  note "case 2: a callback for another login's state was accepted"
grep -q 'state does not match' "$TMP/o2" || note "case 2: the refusal does not say the state did not match"
# Refused before it reached the listener, so the right URL can still be pasted.
{ [ -s "$TMP/state/prod/pid" ] && kill -0 "$(cat "$TMP/state/prod/pid")" 2>/dev/null; } ||
  note "case 2: a refused callback took the listener down"
[ "$(cksum < "$SEC")" = "$before" ] || note "case 2: a refused callback changed the secrets file"

# 3. The right callback stores the token, keeps the still-valid old one, updates ~/.vault-token.
out="$(vl bash "$SCRIPT" finish prod "$cb" 2>&1)"; rc=$?
[ "$rc" = 0 ] || note "case 3: finish exited $rc: $out"
grep -qx 'VAULT_TOKEN_PROD=tok-prod-new-prod' "$SEC" || note "case 3: VAULT_TOKEN_PROD not stored"
grep -qx 'VAULT_TOKEN_PROD_BACKUP=tok-old-prod' "$SEC" || note "case 3: the still-valid old token was not kept as BACKUP"
grep -qx 'OTHER_KEY=keep-me' "$SEC" || note "case 3: an unrelated secret was lost"
[ "$(grep -c '^VAULT_TOKEN_PROD=' "$SEC")" = 1 ] || note "case 3: VAULT_TOKEN_PROD appears more than once"
[ "$(cat "$H/.vault-token")" = tok-prod-new-prod ] || note "case 3: ~/.vault-token not updated for the default env"
mode="$(stat -c '%a' "$SEC" 2>/dev/null || stat -f '%Lp' "$SEC")"; [ "$mode" = 600 ] || note "case 3: secrets file mode $mode, want 600"
printf '%s' "$out" | grep -q 'tok-' && note "case 3: a token value was printed"
printf '%s' "$out" | grep -q 'ttl ' || note "case 3: the result does not report the ttl"

# 4. staging login: ~/.vault-token untouched (the CLI wrote its token into the
#    throwaway HOME), and an old token that no longer works is not kept.
echo new-st > "$TMP/next"; echo "tok-staging-new-st" >> "$TMP/valid"
vl bash "$SCRIPT" start staging >/dev/null 2>&1
vl bash "$SCRIPT" finish staging "$cb" >/dev/null 2>&1 || note "case 4: staging finish failed"
grep -qx 'VAULT_TOKEN_STAGING=tok-staging-new-st' "$SEC" || note "case 4: VAULT_TOKEN_STAGING not stored"
grep -q '^VAULT_TOKEN_STAGING_BACKUP=' "$SEC" && note "case 4: a dead old token was kept as BACKUP"
[ "$(cat "$H/.vault-token")" = tok-prod-new-prod ] || note "case 4: a staging login overwrote ~/.vault-token"

# 5. finish without a running listener says so.
vl bash "$SCRIPT" finish staging "$cb" > "$TMP/o5" 2>&1 && note "case 5: finish with no listener succeeded"
grep -q 'run start first' "$TMP/o5" || note "case 5: no hint to run start"

# 5b. cancel stops a started listener.
vl bash "$SCRIPT" start staging >/dev/null 2>&1
lp="$(cat "$TMP/state/staging/pid" 2>/dev/null)"
vl bash "$SCRIPT" cancel >/dev/null 2>&1
sleep 0.3
{ [ -n "$lp" ] && ! kill -0 "$lp" 2>/dev/null; } || note "case 5b: cancel left the listener running"

# 6. status separates ok, absent and unknown.
out="$(vl env VAULT_DEV_ADDR="$API/dev" bash "$SCRIPT" status prod dev 2>&1)"
printf '%s\n' "$out" | grep -q '^prod: ok' || note "case 6: prod not ok"
printf '%s\n' "$out" | grep -q '^dev: absent' || note "case 6: a missing key is not reported as absent"
out="$(vl bash "$SCRIPT" status qa 2>&1)"
printf '%s\n' "$out" | grep -q '^qa: unknown' || note "case 6: an unset address is not reported as unknown"

if [ "$fails" -ne 0 ]; then
  echo "--- secrets ---"; sed 's/=.*/=<v>/' "$SEC"
  exit 1
fi
echo "ok: vault-login injects every endpoint, checks the callback, stores and keeps tokens right"
