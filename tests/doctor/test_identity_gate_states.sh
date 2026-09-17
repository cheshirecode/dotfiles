#!/usr/bin/env bash
# The vault identity-gate check must tell four answers apart.
#
# bin/doctor.sh reported OK / FAIL / WARN, so "not installed" and "could not
# tell" both landed in WARN and a missing reader read like a passing one.
# The gate has two independent halves — the pre-commit-identity hook being
# installed, and WORKLOG_IDENTITY_DOMAIN being set where a commit would read
# it — and each fails differently:
#
#   armed        hook installed AND domain set            -> OK
#   disarmed     hook installed, domain unset             -> FAIL (reports and skips)
#   hook absent  no hook at all                           -> FAIL (protects nothing)
#   not cloned   vault is not on this machine             -> ABSENT (not a failure)
#
# Each case is built as a scratch vault, so the failure paths are reachable
# rather than asserted.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${DOCTOR_BIN:-$ROOT/bin/doctor.sh}"

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

if [ ! -x "$DOCTOR" ]; then
  echo "test_identity_gate_states NOT RUN — nothing asserted; $DOCTOR missing or not executable." >&2
  exit 2
fi
if ! command -v direnv >/dev/null; then
  echo "test_identity_gate_states NOT RUN — direnv is required to read the domain the way a commit reads it." >&2
  exit 2
fi

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

# Build a vault. $2 = "armed" | "disarmed" | "nohook"
make_vault() {
  local v="$T/$1" mode="$2"
  mkdir -p "$v"
  git init -q "$v"
  ( cd "$v" && git config user.email probe@test && git config user.name probe )
  if [ "$mode" != "nohook" ]; then
    mkdir -p "$v/hooks"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$v/hooks/pre-commit-identity"
    chmod +x "$v/hooks/pre-commit-identity"
    ( cd "$v" && git config core.hooksPath "$v/hooks" )
  fi
  if [ "$mode" = "armed" ]; then
    printf 'export WORKLOG_IDENTITY_DOMAIN=probe.example\n' > "$v/.envrc"
  else
    printf 'export SOMETHING_ELSE=1\n' > "$v/.envrc"
  fi
  direnv allow "$v" >/dev/null 2>&1
  echo "$v"
}

# Only the gate section matters here; read its lines for the vault under test.
gate_lines() {
  WORKLOG_VAULTS="$1" bash "$DOCTOR" 2>&1 \
    | sed -n '/doctor: vault identity gate/,/^doctor: [0-9]/p'
}

armed="$(make_vault armed armed)"
out="$(gate_lines "$armed")"
if printf '%s' "$out" | grep -q "OK .*$armed identity gate armed"; then
  ok "armed vault reports OK"
else
  bad "armed vault did not report OK: $(printf '%s' "$out" | grep -F "$armed")"
fi

disarmed="$(make_vault disarmed disarmed)"
out="$(gate_lines "$disarmed")"
if printf '%s' "$out" | grep -q "FAIL .*$disarmed identity gate DISARMED"; then
  ok "hook installed but domain unset reports FAIL, not OK"
else
  bad "disarmed vault was not reported as FAIL: $(printf '%s' "$out" | grep -F "$disarmed")"
fi

nohook="$(make_vault nohook nohook)"
out="$(gate_lines "$nohook")"
if printf '%s' "$out" | grep -q "FAIL .*$nohook identity hook not installed"; then
  ok "missing hook reports FAIL"
else
  bad "missing hook was not reported as FAIL: $(printf '%s' "$out" | grep -F "$nohook")"
fi

missing="$T/never-cloned"
out="$(gate_lines "$missing")"
if printf '%s' "$out" | grep -q "ABSENT .*$missing not cloned here"; then
  ok "a vault that is not on this machine reports ABSENT, distinct from a broken one"
else
  bad "uncloned vault was not reported as ABSENT: $(printf '%s' "$out" | grep -F "$missing")"
fi

# ABSENT alone must not fail the run; a disarmed gate must.
WORKLOG_VAULTS="$missing" bash "$DOCTOR" >/dev/null 2>&1; absent_rc=$?
WORKLOG_VAULTS="$disarmed" bash "$DOCTOR" >/dev/null 2>&1; disarmed_rc=$?
if [ "$disarmed_rc" -eq 1 ]; then
  ok "a disarmed gate gates the exit code (rc=1)"
else
  bad "disarmed gate did not fail the run (rc=$disarmed_rc)"
fi
if [ "$absent_rc" -ne 1 ]; then
  ok "an absent vault alone does not fail the run (rc=$absent_rc)"
else
  bad "an absent vault failed the run, collapsing absent into broken"
fi

printf 'tests: %d pass, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
