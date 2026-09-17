#!/usr/bin/env bash
# install.sh must generate ~/.env.secrets from the tracked template: present,
# mode 0600, every key EMPTY, and never clobbered on a re-run.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-secrets.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/home"
mkdir -p "$DEST"

run() { (cd "$REPO" && env HOME="$DEST" CODER_SYMLINK_DIR="$DEST" bash install.sh 2>&1); }

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

out="$(run)"
f="$DEST/.env.secrets"

if [ ! -f "$f" ]; then
  note "install.sh did not create $HOME/.env.secrets"
else
  mode="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)"
  [ "$mode" = "600" ] || note "$HOME/.env.secrets mode is $mode, want 600"

  grep -q '^GH_TOKEN_CHESHIRECODE=' "$f" ||
    note "template does not seed the GH_TOKEN_CHESHIRECODE key"

  # The installer must ship a form, never a value. Any KEY=<something> here
  # means a credential reached the tracked template.
  if filled="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.+' "$f")"; then
    note "template ships a non-empty value: $filled"
  fi
fi

# A re-run must preserve what the user filled in. This is the assertion that
# catches an unguarded `cp`, which would silently wipe a working credential.
printf 'GH_TOKEN_CHESHIRECODE=filled-by-hand\n' > "$f"
chmod 600 "$f"
run >/dev/null
grep -q '^GH_TOKEN_CHESHIRECODE=filled-by-hand$' "$f" ||
  note "a re-run overwrote the filled-in $HOME/.env.secrets"

# The repo must not hand a .shell_common.* overlay out to $HOME.
for stray in "$DEST"/.shell_common.*; do
  [ -e "$stray" ] || continue
  case "$(basename "$stray")" in
    .shell_common.local) continue ;; # generated machine-local file, expected
  esac
  note "installer placed $(basename "$stray") into \$HOME from the repo"
done

if [ "$fails" -ne 0 ]; then
  echo "--- installer output ---"
  printf '%s\n' "$out" | tail -15
  exit 1
fi
echo "ok: ~/.env.secrets generated empty at 0600, preserved on re-run"
