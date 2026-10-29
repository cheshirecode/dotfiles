#!/usr/bin/env bash
# Headless Vault OIDC login, for a machine whose browser cannot reach the CLI's
# callback listener (a remote workspace: the listener binds there, the browser
# runs on a laptop). Two steps, so it works from a tool shell as well as a
# terminal:
#
#   bin/vault-login.sh start  ENV        # prints the IdP link; open it, approve
#   bin/vault-login.sh finish ENV URL    # URL = the localhost callback address
#                                        #   the browser then fails to load
#   bin/vault-login.sh status [ENV...]   # ttl and expiry, never the token
#   bin/vault-login.sh cancel            # stop an abandoned login's listener
#
# ENV is a label, not a site: it names the injected address and the stored key.
# Nothing site-specific is in this file; every endpoint and path comes in.
#
#   --addr URL / VAULT_<ENV>_ADDR   Vault address (required; unset is an error)
#   ENV_SECRETS                     secrets file (default ~/.env.secrets); must
#                                   exist -- this never creates a credential file
#   VAULT_LOGIN_PORT                callback port (default 8250)
#   VAULT_LOGIN_STATE               listener state dir
#                                   (default ${XDG_STATE_HOME:-~/.local/state}/vault-login)
#   VAULT_DEFAULT_ENV               the ENV whose token also goes to ~/.vault-token
#                                   (default prod; hvac reads that file)
#   VAULT_BIN                       vault CLI (default vault)
#
# finish stores the token as VAULT_TOKEN_<ENV>, keeps a previous token that
# still authenticates as VAULT_TOKEN_<ENV>_BACKUP, and renews at once: a fresh
# OIDC lease can be one day, shorter than the gap to the next daily renewal.
#
# The login runs in a throwaway HOME, so a staging login cannot overwrite the
# prod token in ~/.vault-token. A listener is stopped by its recorded pid only:
# `pkill -f 'vault login ...'` matches the calling shell's own command line.
#
# Exit status: 0 done; 1 the login or a check failed; 2 bad invocation or
# missing configuration.
set -uo pipefail

die() { printf 'vault-login: %s\n' "$2" >&2; exit "$1"; }
VAULT_BIN="${VAULT_BIN:-vault}"
PORT="${VAULT_LOGIN_PORT:-8250}"
STATE="${VAULT_LOGIN_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/vault-login}"
SECRETS="${ENV_SECRETS:-$HOME/.env.secrets}"
DEFAULT_ENV="${VAULT_DEFAULT_ENV:-prod}"

cmd="${1:-}"; [ $# -gt 0 ] && shift
[ -n "$cmd" ] || die 2 "usage: vault-login.sh start|finish|status|cancel ... (see the header)"

up() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }
addr_for() {  # <env> [--addr value] -> address on stdout
  local v
  v="VAULT_$(up "$1")_ADDR"
  [ -n "${2:-}" ] && { printf '%s' "$2"; return; }
  [ -n "${!v:-}" ] || die 2 "no address for '$1': pass --addr or set \$$v"
  printf '%s' "${!v}"
}
read_key() {  # <key> -> value from the secrets file, empty if absent
  [ -r "$SECRETS" ] || return 0
  sed -n "s/^$1=//p" "$SECRETS" | tail -n 1
}
ttl_of() {  # <addr> <token> -> ttl seconds, empty when refused or unreachable
  local ns=()
  [ -n "${VAULT_NAMESPACE:-}" ] && ns=(-H "X-Vault-Namespace: $VAULT_NAMESPACE")
  curl -sS --max-time 8 "${ns[@]}" -H "X-Vault-Token: $2" "$1/v1/auth/token/lookup-self" 2>/dev/null |
    python3 -c 'import json,sys
try: print(json.load(sys.stdin)["data"]["ttl"])
except Exception: pass' 2>/dev/null
}
days() { python3 -c "import sys; print('%.1fd' % (int(sys.argv[1]) / 86400))" "$1"; }
stop_listener() {
  local p
  for p in "$STATE"/*/pid; do
    [ -s "$p" ] && kill "$(cat "$p")" 2>/dev/null
    rm -f "$p"
  done
}

case "$cmd" in
start)
  env_="${1:-}"; [ -n "$env_" ] || die 2 "usage: start ENV [--addr URL]"; shift
  given=""; [ "${1:-}" = --addr ] && given="${2:-}"
  addr="$(addr_for "$env_" "$given")" || exit 2
  command -v "$VAULT_BIN" >/dev/null 2>&1 || die 2 "vault CLI not found ($VAULT_BIN)"
  stop_listener  # one port, one login at a time
  d="$STATE/$env_"
  { mkdir -p "$d/home" && chmod 0700 "$STATE" "$d" "$d/home"; } || die 1 "cannot create $d"
  rm -f "$d/out.json" "$d/err.log" "$d/url"
  printf '%s' "$addr" > "$d/addr"
  setsid nohup env -u VAULT_TOKEN HOME="$d/home" VAULT_ADDR="$addr" \
    "$VAULT_BIN" login -method=oidc -format=json skip_browser=true port="$PORT" \
    > "$d/out.json" 2> "$d/err.log" < /dev/null &
  echo $! > "$d/pid"
  for _ in $(seq 40); do grep -qE 'https?://[^[:space:]]+' "$d/err.log" 2>/dev/null && break; sleep 0.25; done
  grep -oE 'https?://[^[:space:]]+' "$d/err.log" 2>/dev/null | head -n 1 > "$d/url"
  [ -s "$d/url" ] || { stop_listener; die 1 "no login URL from vault: $(tail -n 3 "$d/err.log" 2>/dev/null)"; }
  cat "$d/url"
  echo "vault-login: open it, approve, then run: $0 finish $env_ '<the localhost:$PORT address the browser shows>'" >&2
  ;;

finish)
  env_="${1:-}"; cb="${2:-}"
  { [ -n "$env_" ] && [ -n "$cb" ]; } || die 2 "usage: finish ENV CALLBACK_URL"
  d="$STATE/$env_"
  { [ -s "$d/pid" ] && kill -0 "$(cat "$d/pid")" 2>/dev/null; } || die 1 "no listener for '$env_'; run start first"
  [ -f "$SECRETS" ] || die 2 "secrets file $SECRETS does not exist; set ENV_SECRETS"
  # The callback must belong to THIS login: same state as the URL start printed.
  # Pasting the other environment's callback otherwise reaches the wrong listener.
  q="$(python3 - "$cb" "$d/url" 2>&1 <<'EOF'
import sys, urllib.parse as u
cb = u.urlsplit(sys.argv[1]); q = dict(u.parse_qsl(cb.query))
want = dict(u.parse_qsl(u.urlsplit(open(sys.argv[2]).read().strip()).query)).get("state")
if cb.path != "/oidc/callback" or "code" not in q or "state" not in q:
    sys.exit("not an OIDC callback URL (want /oidc/callback?code=...&state=...)")
if want and q["state"] != want:
    sys.exit("callback state does not match the login started for this ENV")
print(cb.query)
EOF
)" || die 1 "$q"
  curl -sS -o /dev/null --max-time 20 "http://127.0.0.1:$PORT/oidc/callback?$q" || die 1 "the listener did not take the callback"
  p="$(cat "$d/pid")"
  for _ in $(seq 80); do kill -0 "$p" 2>/dev/null || break; sleep 0.25; done
  rm -f "$d/pid"
  tok="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["auth"]["client_token"])' "$d/out.json" 2>/dev/null)" ||
    die 1 "login did not return a token: $(tail -n 2 "$d/err.log" 2>/dev/null)"
  rm -f "$d/out.json"
  addr="$(cat "$d/addr")"
  granted="$(curl -sS --max-time 10 -X POST -H "X-Vault-Token: $tok" -d '{"increment":"768h"}' \
    "$addr/v1/auth/token/renew-self" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["auth"]["lease_duration"])
except Exception: pass' 2>/dev/null)"
  ttl="$(ttl_of "$addr" "$tok")"
  [ -n "$ttl" ] || die 1 "the new token does not authenticate at $addr"
  key="VAULT_TOKEN_$(up "$env_")"
  old="$(read_key "$key")"
  keep=""; [ -n "$old" ] && [ "$old" != "$tok" ] && [ -n "$(ttl_of "$addr" "$old")" ] && keep="$old"
  python3 - "$SECRETS" "$key" "$tok" "$keep" <<'EOF' || die 1 "could not write $SECRETS"
import os, re, sys, tempfile
path, key, tok, keep = sys.argv[1:5]
want = {key: tok}
if keep:
    want[key + "_BACKUP"] = keep
out, seen = [], set()
for line in open(path).read().splitlines():
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=", line)
    if m and m.group(1) in want:
        if m.group(1) in seen:
            continue
        seen.add(m.group(1)); out.append(m.group(1) + "=" + want[m.group(1)])
    else:
        out.append(line)
out += [k + "=" + v for k, v in want.items() if k not in seen]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)))
os.write(fd, ("\n".join(out) + "\n").encode()); os.close(fd)
os.chmod(tmp, 0o600); os.replace(tmp, path)
EOF
  if [ "$env_" = "$DEFAULT_ENV" ]; then
    (umask 077; printf '%s' "$tok" > "$HOME/.vault-token.tmp") && mv -f "$HOME/.vault-token.tmp" "$HOME/.vault-token" &&
      echo "vault-login: ~/.vault-token updated ($env_ is the default)"
  fi
  [ -n "$granted" ] || echo "vault-login: warning: renew-self failed; the lease may be short" >&2
  echo "vault-login: $env_ logged in, $key stored in $SECRETS, ttl $(days "$ttl")${keep:+; previous token kept as ${key}_BACKUP}"
  unset tok old keep
  ;;

status)
  [ $# -gt 0 ] || set -- prod staging
  rc=0
  for env_ in "$@"; do
    key="VAULT_TOKEN_$(up "$env_")"; v="VAULT_$(up "$env_")_ADDR"; tok="$(read_key "$key")"
    if [ -z "${!v:-}" ]; then echo "$env_: unknown (\$$v unset)"; rc=2
    elif [ -z "$tok" ]; then echo "$env_: absent ($key not in $SECRETS)"; rc=1
    else
      ttl="$(ttl_of "${!v}" "$tok")"
      if [ -n "$ttl" ]; then echo "$env_: ok, ttl $(days "$ttl")"; else echo "$env_: broken (token refused or Vault unreachable)"; rc=1; fi
    fi
  done
  exit "$rc"
  ;;

cancel)
  stop_listener; echo "vault-login: no login listener running"
  ;;

*) die 2 "unknown command '$cmd' (start, finish, status, cancel)" ;;
esac
