#!/usr/bin/env bash
# guard-dispatch.py runs injected guard modules from WORKLOG_GUARDS_PATH, and
# install-hooks.sh wires it only when people/<namespace>/guards/ exists.
# A guard that raises must deny (a broken guard must not read as a pass).

set -uo pipefail

SKILL_BIN="$(cd "$(dirname "$0")/../../bin" && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gd-fixture.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }
run() { printf '%s' "$2" | WORKLOG_GUARDS_PATH="$1" python3 "$SKILL_BIN/guard-dispatch.py"; }
BASH_EV='{"tool_name":"Bash","tool_input":{"command":"git push --force origin b"},"cwd":"/x"}'
READ_EV='{"tool_name":"Read","tool_input":{"file_path":"/x"}}'

G="$TMP/guards"; mkdir -p "$G"
cat > "$G/no_force.py" <<'PY'
TOOLS = ("Bash",)
def check(event):
    if event["tool_name"] != "Bash":
        return "saw a call outside TOOLS"
    cmd = event["tool_input"].get("command", "")
    return "force-push denied" if "--force" in cmd else None
PY
cat > "$G/_helper.py" <<'PY'
raise RuntimeError("a helper is not a guard and must not load")
PY
cat > "$G/test_no_force.py" <<'PY'
raise RuntimeError("a test is not a guard and must not load")
PY

[ -z "$(run "" "$BASH_EV")" ] || note "no WORKLOG_GUARDS_PATH must allow silently"
out="$(run "$G" "$BASH_EV")"
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["permissionDecision"]=="deny" and "[no_force.py] force-push denied" in d["permissionDecisionReason"]' \
  || note "a matching guard must deny with its file name: $out"
[ -z "$(run "$G" '{"tool_name":"Bash","tool_input":{"command":"git push origin b"}}')" ] || note "a guard returning None must allow"
[ -z "$(run "$G" "$READ_EV")" ] || note "TOOLS must limit which tool calls a guard sees"

B="$TMP/broken"; mkdir -p "$B"
printf 'def check(event):\n    raise KeyError("boom")\n' > "$B/raises.py"
out="$(run "$B" "$BASH_EV")"
printf '%s' "$out" | grep -q 'guard raises.py failed (KeyError' || note "a raising guard must deny with its error: $out"

out="$(run "$TMP/empty${PATH_SEP:-:}$G" "$BASH_EV")"
printf '%s' "$out" | grep -q 'no_force.py' || note "every directory on the path must be searched"

# Installer: guards dir present -> one PreToolUse entry carrying the path;
# absent -> none; uninstall removes it; foreign PreToolUse entries survive.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
V="$TMP/vault"; git init -q "$V"; git -C "$V" config worklog.namespace someone
S="$TMP/settings.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"python3 /elsewhere/own_guard.py"}]}]}}' > "$S"
CLAUDE_SETTINGS="$S" bash "$SKILL_BIN/install-hooks.sh" --data-root="$V" --write >/dev/null 2>&1 || note "install without guards failed"
grep -q guard-dispatch.py "$S" && note "dispatcher installed although people/someone/guards is absent"
mkdir -p "$V/people/someone/guards"
CLAUDE_SETTINGS="$S" bash "$SKILL_BIN/install-hooks.sh" --data-root="$V" --write >/dev/null 2>&1 || note "install with guards failed"
grep -q "WORKLOG_GUARDS_PATH=\\\\\"$V/people/someone/guards\\\\\" python3 $SKILL_BIN/guard-dispatch.py" "$S" \
  || note "dispatcher entry missing or without the guards path: $(grep -o 'WORKLOG_GUARDS_PATH[^,]*' "$S")"
grep -q own_guard.py "$S" || note "install removed a PreToolUse entry it does not own"
CLAUDE_SETTINGS="$S" bash "$SKILL_BIN/install-hooks.sh" --data-root="$V" --uninstall --write >/dev/null 2>&1
grep -q guard-dispatch.py "$S" && note "uninstall left the dispatcher"
grep -q own_guard.py "$S" || note "uninstall removed a PreToolUse entry it does not own"

[ "$fails" -eq 0 ] || exit 1
echo "ok: guards are injected per namespace, a broken guard denies, the installer wires them only when present"
