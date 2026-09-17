#!/usr/bin/env bash
# Read ONE key from the machine-local credential file (~/.env.secrets).
#
#   env-secret.sh GH_TOKEN_CHESHIRECODE      -> prints the value, rc 0
#   env-secret.sh MISSING_KEY                -> prints nothing, rc 1
#
# One key at a time, never the whole file. Callers live in trees with
# different identities (personal vs work), and sourcing the file would put
# every credential into all of them. See templates/env.secrets.example.
#
# The same logic is inlined in .envrc, which is symlinked to ~/.envrc and so
# cannot depend on this repo's path. tests/shell/test_env_secret_reader.sh
# asserts the two agree; change both or neither.
set -uo pipefail

key="${1:-}"
if [ -z "$key" ]; then
  echo "usage: env-secret.sh KEY" >&2
  exit 2
fi

# Location, in order. WSL and Git Bash put $HOME in different places, and
# Windows-native shells set USERPROFILE instead of HOME.
#
# A Windows drive mounted into WSL (/mnt/c/...) is NOT on this list. DrvFs
# reports 0777 whatever you chmod, so a credential file there cannot be made
# unreadable to other accounts, and a silent read from it would look exactly
# like a safe one. Keep the file on the Linux filesystem under WSL.
for candidate in "${ENV_SECRETS_FILE:-}" "$HOME/.env.secrets" "${USERPROFILE:-}/.env.secrets"; do
  [ -n "$candidate" ] || continue
  [ -r "$candidate" ] || continue
  file="$candidate"
  break
done

if [ -z "${file:-}" ]; then
  echo "env-secret.sh: no readable ~/.env.secrets; run install.sh to create it" >&2
  exit 1
fi

# Mode check, loud. A file at 0644 is readable by every account on the box,
# and a reader that quietly used it would turn a permissions mistake into a
# silent one. Warn and still return the value: refusing would break a caller
# mid-task, and the operator needs to see the cause, not a missing token.
mode="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null || echo unknown)"
case "$mode" in
  600|400) ;;
  unknown) echo "env-secret.sh: cannot read mode of $file" >&2 ;;
  *) echo "env-secret.sh: $file is mode $mode, want 600 — run: chmod 600 $file" >&2 ;;
esac

# Anchored at the line start, first match only. An unanchored pattern would
# also match GH_TOKEN_CHESHIRECODE when asked for GH_TOKEN; a greedy one would
# take the last assignment instead of the first.
value="$(sed -n "s/^[[:space:]]*${key}=//p" "$file" | head -1)"
value="${value%\"}"; value="${value#\"}"
value="${value%\'}"; value="${value#\'}"
# Strip a trailing CR so a file edited on Windows still yields a usable token.
value="${value%$'\r'}"

[ -n "$value" ] || exit 1
printf '%s\n' "$value"
