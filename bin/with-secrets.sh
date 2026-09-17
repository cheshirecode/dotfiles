#!/usr/bin/env bash
# Run a command with named keys from ~/.env.secrets exported into it, and
# nowhere else. The cross-platform counterpart to the sandbox's tmpfs pipe:
# same idea (a credential reaches one process, not the whole shell), but for a
# laptop, WSL or Git Bash where there is no container.
#
#   with-secrets.sh ANTHROPIC_API_KEY -- claude
#   with-secrets.sh GH_TOKEN:GH_TOKEN_CHESHIRECODE -- gh pr list
#   with-secrets.sh OPENROUTER_API_KEY -- opencode
#   with-secrets.sh CURSOR_API_KEY -- cursor-agent
#
# An argument is either KEY (export KEY) or ENVVAR:KEY (export ENVVAR from
# KEY). The second form exists because the file names a credential by owner,
# GH_TOKEN_CHESHIRECODE, while a tool wants the plain GH_TOKEN.
#
# Why not `export` these in a shell rc: this repo's .envrc gives each
# directory tree its own identity, and a credential exported in a login shell
# is present in every tree. Per-command is the smallest scope that still
# works on a machine with no keychain.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
READER="$HERE/env-secret.sh"

usage() {
  echo "usage: with-secrets.sh KEY|ENVVAR:KEY ... -- command [args]" >&2
  exit 2
}

specs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    -h|--help) usage ;;
    -*) echo "with-secrets.sh: unknown option $1" >&2; usage ;;
    *) specs+=("$1"); shift ;;
  esac
done

[ "${#specs[@]}" -gt 0 ] || usage
[ $# -gt 0 ] || usage

env_args=()
missing=()
for spec in "${specs[@]}"; do
  case "$spec" in
    *:*) envvar="${spec%%:*}"; key="${spec#*:}" ;;
    *)   envvar="$spec";       key="$spec" ;;
  esac
  if value="$("$READER" "$key")"; then
    env_args+=("$envvar=$value")
  else
    # Named but absent is reported, never silent. A tool that also supports
    # an OAuth login still works without the key, so this is a warning and
    # not a hard failure -- but an unset credential must not look like a set
    # one, which is what a silent skip would give you.
    missing+=("$key")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "with-secrets.sh: no value for: ${missing[*]} (add it to ~/.env.secrets)" >&2
fi

# `env` places the values in the child's environment only. The parent shell
# never holds them, so they cannot leak into a sibling directory tree.
exec env "${env_args[@]+"${env_args[@]}"}" "$@"
