#!/usr/bin/env bash
# restore-home-links.sh must leave glab logged in after a restart. glab reads
# its token from its own config (on the overlay) or the environment, never from
# ~/.git-credentials, so git could push to GitLab while `glab auth status`
# said "No token found" (2026-10-09). A stateful stub glab stands in for the
# real one: it stores what `auth login --stdin` reads and accepts only GOOD.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/restore-home-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/restore-glab-token.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

GOOD=fixture-token-good
fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$TMP/bin" "$TMP/home"
# Like the real glab, an exported GITLAB_TOKEN wins over the stored token for
# both `config get token` and `auth status`. The hook sources the secrets file,
# so a stub without this override passed while the live hook never logged in:
# its stored-token check always matched the environment.
cat > "$TMP/bin/glab" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TMP/glab.calls"
stored() { if [ -n "\${GITLAB_TOKEN:-}" ]; then printf '%s' "\$GITLAB_TOKEN"; else cat "$TMP/glab.token" 2>/dev/null; fi; }
case "\$*" in
  "config get git_protocol"*) echo https ;;
  "config get token --host gitlab.com") stored ;;
  "auth login"*"--stdin"*) cat > "$TMP/glab.token" ;;
  "auth status"*) [ "\$(stored)" = "$GOOD" ] ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/glab"

run() {  # run <secrets-file> -> OUT
  : > "$TMP/glab.calls"
  OUT=$(timeout 60 env -i PATH="$TMP/bin:$PATH" HOME="$TMP/home" RESTORE_GLAB_TIMEOUT=5 \
    WORKLOG_HOOKS_REPO='' ENV_SECRETS="$1" AWS_CANON=/nonexistent AWS_SSO_CACHE='' \
    VAULT_STAMP="$TMP/stamp" bash "$SCRIPT" 2>&1)
}
logins() { grep -c '^auth login' "$TMP/glab.calls"; }

printf 'GITLAB_TOKEN=%s\n' "$GOOD" > "$TMP/good.env"
printf 'GITLAB_TOKEN=%s\n' fixture-token-bad > "$TMP/bad.env"
printf 'OTHER=1\n' > "$TMP/none.env"

# 1. Fresh overlay: no stored token, so it logs in and says so.
run "$TMP/good.env"
[ "$(logins)" = 1 ] || note "fresh config: auth login ran $(logins) times, want 1"
[ "$(cat "$TMP/glab.token" 2>/dev/null)" = "$GOOD" ] || note "fresh config: glab did not receive the token on stdin"
grep -q 'glab logged in to gitlab.com' <<<"$OUT" || note "fresh config: no 'glab logged in' note"
grep -qF "$GOOD" <<<"$OUT" && note "the token was printed in the hook output"
grep -qF "$GOOD" "$TMP/glab.calls" && note "the token was passed on the command line"

# 2. Already logged in with the same token: no churn, no note.
run "$TMP/good.env"
[ "$(logins)" = 0 ] || note "same token: logged in again ($(logins) times)"
grep -q 'glab' <<<"$OUT" && note "same token: printed a glab note: $(grep glab <<<"$OUT")"

# 3. A token glab refuses is reported, not claimed as a login.
rm -f "$TMP/glab.token"
run "$TMP/bad.env"
grep -q 'glab NOT logged in' <<<"$OUT" || note "refused token: no 'NOT logged in' note"
grep -q 'glab logged in to' <<<"$OUT" && note "refused token: claimed a login"

# 4. No GitLab token in the secrets file: glab is left alone.
rm -f "$TMP/glab.token"
run "$TMP/none.env"
[ "$(logins)" = 0 ] || note "no token: attempted a login"

# Inert-lane guard: the stub must have been reached at all.
grep -q '^config get git_protocol' "$TMP/glab.calls" || note "glab was never called, so nothing was tested"

[ "$fails" -eq 0 ] || { printf '%s\n' "$OUT"; exit 1; }
echo "ok: the session-start hook logs glab in from the secrets file, quietly when already done, and reports a refused token"
