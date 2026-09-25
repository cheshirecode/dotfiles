#!/usr/bin/env bash
# Read ONE key from the machine-local credential file (~/.env.secrets).
#
#   env-secret.sh GH_TOKEN_CHESHIRECODE      -> prints the value, rc 0
#   env-secret.sh MISSING_KEY                -> rc 1, stderr says "not in"
#   env-secret.sh BLANK_KEY                  -> rc 1, stderr says "no value"
#   env-secret.sh KEY, with no secrets file  -> rc 2, stderr says "no readable"
#   env-secret.sh          (no argument)     -> rc 2, usage
#
# Three outcomes, not two. rc 1 is an answer about the KEY -- it has no value,
# and the fix is to edit the file. rc 2 means the question could not be asked at
# all: a bad invocation, or no credential file to look in, where the fix is to
# run install.sh. A missing file returning rc 1 put "you have not filled this in"
# and "there is nothing to fill in" behind the same number.
#
# Nothing but the value ever reaches stdout, so a caller capturing it is
# unaffected by the explanations; they go to stderr.
#
# One key at a time, never the whole file. Callers live in trees with
# different identities (personal vs work), and sourcing the file would put
# every credential into all of them. See templates/env.secrets.example.
#
# This is the only reader. .envrc.example calls it rather than inlining a
# copy; tests/shell/test_env_secret_reader.sh pins the key-selection contract.
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
  # rc 2, not 1: no file is not an answer about the key. The remedy is
  # install.sh, where rc 1's remedy is editing a line -- and a caller that
  # retried the "fill it in" path here would be waiting on a file that does
  # not exist.
  echo "env-secret.sh: no readable ~/.env.secrets; run install.sh to create it" >&2
  exit 2
fi

# Mode check, loud. A file at 0644 is readable by every account on the box,
# and a reader that quietly used it would turn a permissions mistake into a
# silent one. Warn and still return the value: refusing would break a caller
# mid-task, and the operator needs to see the cause, not a missing token.
mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo unknown)"
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

# "Key not in the file" and "key in the file but blank" need different fixes —
# add the line versus fill it in — and rc 1 alone cannot say which. The rc
# stays 1 for both: callers branch on it, and a blank value must never read as
# success. Only the explanation is new. Same anchor as the sed above, so a
# prefix key (GH_TOKEN) is still reported absent when only GH_TOKEN_SUFFIX is
# present, rather than being described as the empty form of a key it is not.
if [ -z "$value" ]; then
  if grep -q "^[[:space:]]*${key}=" "$file"; then
    echo "env-secret.sh: $key is present in $file but has no value — fill it in" >&2
  else
    echo "env-secret.sh: $key is not in $file — add it, or check the spelling" >&2
  fi
  exit 1
fi
printf '%s\n' "$value"
