#!/usr/bin/env bash
# Log in to AWS SSO and print ONE clickable URL with the device code already in
# it, so there is no code to read off a screen and retype.
#
#   bin/sso-login.sh --session super
#   bin/sso-login.sh --session super --profile default   # verify that profile after
#
# `aws sso login --no-browser` already emits this URL; it just buries it under
# the bare device URL and the code on separate lines, which is what leads to
# copying the code by hand. This prints the autofill link alone, waits for the
# login, and then answers the question the login itself does not: whether the
# token that landed can actually refresh.
#
# Nothing here is site-specific. The start URL comes from the caller's own
# ~/.aws/config at runtime and is never written down in this repo.
#
# Exit status: 0 logged in; 1 the login failed or timed out; 2 bad invocation.
set -uo pipefail

SESSION=""; PROFILE=""; WAIT=600
die_usage() { printf 'sso-login: %s\n' "$*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session) SESSION="${2:-}"; [ -n "$SESSION" ] || die_usage "usage: --session NAME"; shift 2 ;;
    --profile) PROFILE="${2:-}"; [ -n "$PROFILE" ] || die_usage "usage: --profile NAME"; shift 2 ;;
    --wait)    WAIT="${2:-}";    [ -n "$WAIT" ]    || die_usage "usage: --wait SECONDS"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" >&2; exit 2 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
[ -n "$SESSION" ] || die_usage "--session is required (the [sso-session NAME] block in ~/.aws/config)"
command -v aws >/dev/null 2>&1 || die_usage "aws CLI not found"

# An already-running login is reported, never killed. Killing by pattern once
# took out a login a human had just started by hand: `pkill -f 'aws sso login'`
# also matches the shell whose own command line contains that text.
running="$(pgrep -f "aws sso login --sso-session $SESSION" 2>/dev/null | grep -v "^$$\$" | head -3)"
if [ -n "$running" ]; then
  echo "sso-login: a login for '$SESSION' is already running (pid $(echo $running | tr '\n' ' '))." >&2
  echo "sso-login: finish or abandon it first; its device code is still valid for a few minutes." >&2
  exit 2
fi

LOG="$(mktemp "${TMPDIR:-/tmp}/sso-login.XXXXXX")"

# Plain background job, NOT setsid. setsid puts the poller in a new session, so
# the shell's job table no longer tracks it: `%1` then refers to a wrapper that
# has already exited, and the wait below either falls through immediately or
# spins against the wrong process. Measured: the poller was still waiting for
# its code while this script sat in a loop that could not see it. Keep the pid.
aws sso login --sso-session "$SESSION" --no-browser >"$LOG" 2>&1 </dev/null &
POLLER=$!
# Do not leave a poller holding a live device code if this script is interrupted.
trap 'kill "$POLLER" 2>/dev/null; rm -f "$LOG"' EXIT INT TERM

url=""
for _ in $(seq 1 30); do
  url="$(grep -oE 'https://[^[:space:]]*user_code=[A-Za-z0-9-]+' "$LOG" | head -1)"
  [ -n "$url" ] && break
  grep -qi 'error' "$LOG" && break
  sleep 1
done

if [ -z "$url" ]; then
  echo "sso-login: no device URL appeared. aws said:" >&2
  sed 's/^/  /' "$LOG" >&2
  exit 1
fi

code="$(printf '%s' "$url" | grep -oE '[A-Za-z0-9]{4}-[A-Za-z0-9]{4}' | head -1)"
echo
echo "  Open this — the code is already in the link:"
echo
echo "    $url"
echo
[ -n "$code" ] && echo "  (code $code, if the page asks for it)"
echo "  Device codes expire in about 10 minutes."
echo

# Wait for the poller to exit rather than for a fixed time: it exits as soon as
# the code is approved, and on its own when the code expires.
# Wait on the pid, not on a job spec. The poller exits by itself the moment the
# code is approved, and again when the code expires, so this needs no polling of
# its own beyond checking the process is alive.
waited=0
while kill -0 "$POLLER" 2>/dev/null && [ "$waited" -lt "$WAIT" ]; do sleep 3; waited=$((waited+3)); done
if kill -0 "$POLLER" 2>/dev/null; then
  kill "$POLLER" 2>/dev/null
  echo "sso-login: gave up after ${WAIT}s and stopped the poller." >&2
  exit 1
fi

if grep -qi 'Successfully logged into' "$LOG"; then
  echo "sso-login: logged in."
elif grep -qi 'InvalidGrantException\|expired' "$LOG"; then
  echo "sso-login: the device code expired before it was approved. Run again." >&2
  exit 1
else
  echo "sso-login: login did not confirm within ${WAIT}s. aws said:" >&2
  tail -3 "$LOG" | sed 's/^/  /' >&2
  exit 1
fi

# The login succeeding is not the same as getting a refreshable token: under the
# legacy per-profile layout the token has no refreshToken and expires hard.
python3 - <<'PY' || true
import json, glob, os, datetime
now = datetime.datetime.now(datetime.timezone.utc)
for f in glob.glob(os.path.expanduser("~/.aws/sso/cache/*.json")):
    try: d = json.load(open(f))
    except Exception: continue
    if "accessToken" not in d: continue
    try:
        t = datetime.datetime.fromisoformat(d["expiresAt"].replace("Z", "+00:00"))
    except Exception:
        continue
    if t <= now: continue
    hrs = (t - now).total_seconds() / 3600
    if "refreshToken" in d:
        print(f"  token valid {hrs:.1f}h, refreshable — it renews silently until the "
              f"Identity Center session duration is reached")
    else:
        print(f"  token valid {hrs:.1f}h, NO refreshToken — expect a login every session "
              f"(is the profile still on the legacy sso_start_url layout?)")
    break
PY

if [ -n "$PROFILE" ]; then
  if aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
    echo "  profile '$PROFILE': OK"
  else
    echo "  profile '$PROFILE': still failing" >&2
    exit 1
  fi
fi
