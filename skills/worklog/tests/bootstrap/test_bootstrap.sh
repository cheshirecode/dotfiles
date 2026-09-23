#!/usr/bin/env bash
# bootstrap.sh: a worklog instance from nothing, one per (machine, login, vault).
#
# Pins three measured defects:
#   - a shell with no direnv resolved the namespace from the git email, so a
#     vault whose .envrc said WORKLOG_LDAP=oss wrote as `cheshirecode`
#   - the identity hook read WORKLOG_IDENTITY_DOMAIN from env only, so a tool
#     shell skipped the check
#   - init-new-data-repo.sh committed the machine-local .envrc
#
# Every shell below is `env -i`: no direnv, no WORKLOG_*, no git identity.
# `$?` after `[[ ]]` is the status each check reads, by design.
# shellcheck disable=SC2319
set -uo pipefail
unset BASH_ENV

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0 cases=0
check() { # check <label> <status>
  cases=$((cases + 1))
  if [[ "$2" == 0 ]]; then echo "ok: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi
}
# bare <home> <cmd...> — a login with nothing: empty HOME, minimal env.
bare() {
  local home="$1"; shift
  mkdir -p "$home"
  env -i HOME="$home" PATH="$PATH" TMPDIR="$TMP/tmp" GIT_CONFIG_NOSYSTEM=1 \
    ${PYTHONPATH:+PYTHONPATH="$PYTHONPATH"} "$@"
}
mkdir -p "$TMP/tmp"
field() { sed -n "s/^$1=//p" <<<"$2" | head -1; }

# ------------------------------------------------ 1. bare login, no identity
A="$TMP/machine-a"
out="$(bare "$A" bash "$BIN/bootstrap.sh" apply --repo "$A/_worklog" --ns alice --instance host-a/alice)"; rc=$?
check "bare apply exits 0" "$rc"
[[ "$(field ACTION "$out")" == created ]]; check "bare apply creates a vault" $?
[[ "$(field IDENTITY "$out")" == placeholder* ]]; check "no identity anywhere -> IDENTITY=placeholder" $?
[[ "$(field VERIFY "$out")" == "ok tool-shell namespace=alice" ]]; check "tool shell resolves namespace alice" $?
git -C "$A/_worklog" rev-parse --verify -q HEAD >/dev/null; check "first commit exists without a global identity" $?
if git -C "$A/_worklog" ls-files --error-unmatch .envrc >/dev/null 2>&1; then r=1; else r=0; fi
check ".envrc is not tracked" "$r"
[[ -d "$A/_worklog/people/alice/active" ]]; check "namespace dir created" $?
pre="$(cd "$A/_worklog" && bare "$A" bash "$BIN/preamble.sh" --minimal 2>/dev/null)"
[[ "$(field INSTANCE "$pre")" == host-a/alice ]]; check "preamble reports INSTANCE" $?
grep -q '^!! identity: placeholder' <<<"$pre"; check "preamble warns on placeholder identity" $?
[[ "$(field LDAP "$pre")" == alice ]]; check "preamble LDAP from clone config" $?

# ------------------------------------ 2. namespace differs from email local part
# The oss-vault shape: namespace `oss`, author `someone@users.noreply...`.
V="$TMP/login-b"
out="$(bare "$V" bash "$BIN/bootstrap.sh" apply --repo "$V/oss/_worklog" --ns oss \
  --name someone --email 123+someone@users.noreply.github.com)"; rc=$?
check "apply with explicit ns/email exits 0" "$rc"
got="$(cd "$V/oss/_worklog" && bare "$V" bash -c ". '$BIN/_lib.sh'; resolve_ldap")"
[[ "$got" == oss ]]; check "no-direnv shell resolves ns=oss, not the email local part (got '$got')" $?
(cd "$V/oss/_worklog" && bare "$V" bash -c ". '$BIN/_lib.sh'; verify_provenance") >/dev/null 2>&1
check "provenance accepts clone-config namespace" $?
[[ "$(git -C "$V/oss/_worklog" config worklog.identityDomain)" == users.noreply.github.com ]]
check "identity domain derived from email" $?

# ------------------------------------- 3. second vault, same login, own identity
out="$(bare "$V" bash "$BIN/bootstrap.sh" apply --repo "$V/work/_worklog" --ns wk \
  --name "W K" --email wk@corp.example)"; rc=$?
check "second vault apply exits 0" "$rc"
got="$(cd "$V/work/_worklog" && bare "$V" bash -c ". '$BIN/_lib.sh'; resolve_ldap")"
[[ "$got" == wk ]]; check "second vault resolves its own ns (got '$got')" $?
got="$(cd "$V/oss/_worklog" && bare "$V" bash -c ". '$BIN/_lib.sh'; resolve_ldap")"
[[ "$got" == oss ]]; check "first vault unchanged after second apply" $?
# Wrong identity in the work vault: the hook must refuse from a tool shell.
hook_out="$(cd "$V/work/_worklog" && bare "$V" env GIT_AUTHOR_EMAIL=someone@users.noreply.github.com \
  GIT_AUTHOR_NAME=x bash "$BIN/git-hooks/pre-commit-identity" 2>&1)"; rc=$?
[[ "$rc" != 0 ]] && grep -q 'does not match this vault' <<<"$hook_out"
check "identity hook refuses wrong domain without WORKLOG_IDENTITY_DOMAIN env" $?
(cd "$V/work/_worklog" && bare "$V" bash "$BIN/git-hooks/pre-commit-identity") >/dev/null 2>&1
check "identity hook accepts the vault's own author" $?
probe="$(bare "$V" bash "$BIN/bootstrap.sh" probe)"
[[ "$(field VAULTS "$probe")" == 2 ]]; check "probe lists both vaults" $?
grep -q $'^vault\t.*/oss/_worklog\tnone\toss\t' <<<"$probe"; check "probe row carries the oss vault namespace" $?
# Two accounts on one host, as `gh auth status` prints them (with the ✓ prefix
# that once shifted the host field to the word `to`).
mkdir -p "$TMP/stub"
cat > "$TMP/stub/gh" <<'GH'
#!/bin/sh
printf 'github.com\n  ✓ Logged in to github.com account perso (keyring)\n  - Active account: true\n  ✓ Logged in to github.com account work (keyring)\n  - Active account: false\n'
GH
chmod +x "$TMP/stub/gh"
probe="$(PATH="$TMP/stub:$PATH" bare "$V" bash "$BIN/bootstrap.sh" probe)"
[[ "$(field GH_ACCOUNTS "$probe")" == "github.com:perso*,github.com:work" ]]
check "probe lists every gh account and marks the active one" $?

# ------------------------------------------ 4. second machine joins a remote
git clone -q --bare "$A/_worklog" "$TMP/remote.git"
B="$TMP/machine-b"
out="$(bare "$B" bash "$BIN/bootstrap.sh" apply --repo "$B/_worklog" --remote "$TMP/remote.git" \
  --ns alice --email alice@example.org --instance host-b/alice)"; rc=$?
check "second machine apply exits 0" "$rc"
[[ "$(field ACTION "$out")" == cloned ]]; check "second machine clones the remote" $?
[[ "$(git -C "$B/_worklog" config worklog.instance)" != "$(git -C "$A/_worklog" config worklog.instance)" ]]
check "machines share a vault but differ in worklog.instance" $?
[[ "$(git -C "$B/_worklog" rev-parse HEAD)" == "$(git -C "$A/_worklog" rev-parse HEAD)" ]]
check "clone did not add a commit on top of the remote" $?

# ------------------------------------------------ 5. re-run and refusal rules
out="$(bare "$V" bash "$BIN/bootstrap.sh" apply --repo "$V/oss/_worklog")"; rc=$?
check "re-run apply exits 0" "$rc"
[[ "$(git -C "$V/oss/_worklog" config user.email)" == 123+someone@users.noreply.github.com ]]
check "re-run keeps the clone's own email" $?
[[ "$(field NS "$out")" == oss ]]; check "re-run keeps the clone's own namespace" $?
bare "$V" bash "$BIN/bootstrap.sh" apply --repo "$V/work/_worklog" --email wk@newcorp.example >/dev/null
[[ "$(git -C "$V/work/_worklog" config worklog.identityDomain)" == newcorp.example ]]
check "a new --email re-derives worklog.identityDomain" $?
[[ "$(field VAULTS_SCAN "$probe")" == complete ]]; check "probe reports a complete vault scan" $?
bare "$B" bash "$BIN/bootstrap.sh" apply --repo "$B/_worklog" --remote "$TMP/other.git" >/dev/null 2>&1; rc=$?
[[ "$rc" == 3 ]]; check "different remote on an existing clone is refused (exit 3, got $rc)" $?
mkdir -p "$TMP/notempty"; : > "$TMP/notempty/file"
bare "$B" bash "$BIN/bootstrap.sh" apply --repo "$TMP/notempty" >/dev/null 2>&1; rc=$?
[[ "$rc" == 3 ]]; check "non-empty non-clone target is refused (exit 3, got $rc)" $?
bare "$B" bash "$BIN/bootstrap.sh" apply >/dev/null 2>&1; rc=$?
[[ "$rc" == 2 ]]; check "apply without --repo is a usage error (exit 2, got $rc)" $?

# Inert-lane guard: fewer cases than written means a section stopped running.
# Count the call sites (`check "` at line start or after `; `), minus this guard.
# The pattern cannot match its own line: `)?` sits between `; ` and `check`.
want=$(( $(grep -cE '^(.*; )?check "' "$0") - 1 ))
(( cases >= want )); check "ran $cases of at least $want checks" $?

echo "bootstrap: $((cases - fails))/$cases passed"
(( fails == 0 ))
