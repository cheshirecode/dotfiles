#!/usr/bin/env bash
# install.sh must make ~/.bashrc a machine-local stub that sources the tracked
# .bashrc, so the Coder template's `cat >> ~/.bashrc` never lands in a checkout.
# A pure append already sitting in a linked tracked file is carried into the
# stub and the tracked file is put back to HEAD; any other edit is left alone.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-bashrc.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
MARK='# dotfiles install.sh: sources the tracked .bashrc. Lines below are machine-local.'

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

run_install() {  # <home>
  (cd "$REPO" && env HOME="$1" CODER_SYMLINK_DIR="$1" HOOK_BIN_DIR="$1/hookbin" \
    DOTFILES_PRIMARY="$TMP/no-primary" bash install.sh 2>&1)
}

# A tracked .bashrc in its own repo, standing in for a checkout ~/.bashrc used to link to.
mk_linked_repo() {  # <dir>
  mkdir -p "$1" && git -C "$1" init -q &&
    printf 'echo tracked-line\n' > "$1/.bashrc" &&
    git -C "$1" add .bashrc &&
    git -C "$1" -c user.name=t -c user.email=t@example.invalid -c core.hooksPath=/dev/null commit -qm init
}

repo_bashrc_before="$(git -C "$REPO" hash-object .bashrc 2>/dev/null || cksum < "$REPO/.bashrc")"

# --- Case 1: symlink into a checkout whose .bashrc carries a template append.
H1="$TMP/h1"; mkdir -p "$H1"; mk_linked_repo "$TMP/old"
printf '# --- template-block (example) ---\necho template-line\n' >> "$TMP/old/.bashrc"
ln -s "$TMP/old/.bashrc" "$H1/.bashrc"
out1="$(run_install "$H1")"

if [ -L "$H1/.bashrc" ] || [ ! -f "$H1/.bashrc" ]; then
  note "case 1: ~/.bashrc is still a symlink, not a stub"
else
  [ "$(head -n 1 "$H1/.bashrc")" = "$MARK" ] || note "case 1: stub does not start with the marker"
  [ "$(sed -n 2p "$H1/.bashrc")" = ". \"$REPO/.bashrc\"" ] || note "case 1: stub line 2 does not source $REPO/.bashrc"
  grep -qx 'echo template-line' "$H1/.bashrc" || note "case 1: the appended template line was not carried into the stub"
fi
[ -z "$(git -C "$TMP/old" status --porcelain)" ] || note "case 1: the linked checkout's .bashrc was not put back to HEAD"

# --- Case 2: the template appends to the stub, and a rerun keeps it.
printf 'echo appended-after-install\n' >> "$H1/.bashrc"
run_install "$H1" >/dev/null
grep -qx 'echo appended-after-install' "$H1/.bashrc" || note "case 2: a rerun dropped a line appended to the stub"
grep -qx 'echo template-line' "$H1/.bashrc" || note "case 2: a rerun dropped the carried template line"
[ "$(grep -cxF "$MARK" "$H1/.bashrc")" = 1 ] || note "case 2: a rerun duplicated the stub header"

# --- Case 3: an edit to the tracked lines is not a pure append; leave the checkout alone.
H3="$TMP/h3"; mkdir -p "$H3"; mk_linked_repo "$TMP/edited"
printf 'echo someone-edited\n' > "$TMP/edited/.bashrc"
ln -s "$TMP/edited/.bashrc" "$H3/.bashrc"
run_install "$H3" >/dev/null
grep -qx 'echo someone-edited' "$TMP/edited/.bashrc" || note "case 3: an edited tracked .bashrc was reverted"
grep -q 'someone-edited' "$H3/.bashrc" 2>/dev/null && note "case 3: an edit to tracked lines was carried into the stub"

# --- Case 4: a stub left by a checkout that moved is repointed, machine-local lines kept.
H4="$TMP/h4"; mkdir -p "$H4"
printf '%s\n. "/gone/dotfiles/.bashrc"\necho local-line\n' "$MARK" > "$H4/.bashrc"
run_install "$H4" >/dev/null
[ "$(sed -n 2p "$H4/.bashrc")" = ". \"$REPO/.bashrc\"" ] || note "case 4: a stale stub was not repointed"
grep -qx 'echo local-line' "$H4/.bashrc" || note "case 4: repointing dropped a machine-local line"

repo_bashrc_after="$(git -C "$REPO" hash-object .bashrc 2>/dev/null || cksum < "$REPO/.bashrc")"
[ "$repo_bashrc_before" = "$repo_bashrc_after" ] || note "the checkout's own .bashrc changed during the run"
printf '%s\n' "$out1" | grep -q 'Dotfiles installation complete.' || note "installer did not reach its last line"

if [ "$fails" -ne 0 ]; then
  echo "--- installer output (case 1) ---"
  printf '%s\n' "$out1" | tail -15
  exit 1
fi
echo "ok: ~/.bashrc is a stub; appends stay machine-local; edits and moves handled"
