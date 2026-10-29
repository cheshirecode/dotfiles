#!/usr/bin/env bash
# Make the impeccable design skill available ON DEMAND, with no hooks.
#
#   install-impeccable.sh           dry run: say what would change
#   install-impeccable.sh --write   apply
#
# impeccable ships as a Claude Code plugin whose hooks run its downloaded
# engine at every session start and after every Edit/Write, in every session,
# with that session's environment. Its own off switch only silences them, and
# its per-edit check is ON by default (measured 2026-10-21: `hooks status`
# said enabled with no config, and a UI write got findings injected). So the
# plugin is never enabled here. The skill and three of its agents are linked
# from the marketplace clone as plain user-level files, which carry no hooks.
# impeccable-asset-producer is left out: it calls ${CLAUDE_PLUGIN_ROOT},
# which exists only inside an enabled plugin.
#
# Settings `env` gains IMPECCABLE_HOOK_DISABLED=1 (backstop if the plugin is
# ever re-enabled), IMPECCABLE_NO_TELEMETRY=1, and IMPECCABLE_HOME on a
# persistent volume when there is one (the engine is 21 MB; $HOME may be wiped
# on restart). Update with `claude plugin marketplace update impeccable`.
#
# Overridable for tests: CLAUDE_BIN, CLAUDE_HOME, IMPECCABLE_CACHE_ROOT
# (empty = leave IMPECCABLE_HOME unset).

set -uo pipefail

WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1
CLAUDE="${CLAUDE_BIN:-claude}"
CH="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS="$CH/settings.json"
MP="$CH/plugins/marketplaces/impeccable/plugin"
PLUGIN=impeccable@impeccable
AGENTS="impeccable-documenter impeccable-finish-reviewer impeccable-manual-edit-applier"
if [ -z "${IMPECCABLE_CACHE_ROOT+x}" ]; then
  IMPECCABLE_CACHE_ROOT=""
  [ -d /workspace ] && [ -w /workspace ] && IMPECCABLE_CACHE_ROOT=/workspace/.impeccable
fi

say() { echo "install-impeccable: $*"; }
act() {  # act <description> <command...>
  if [ "$WRITE" = 1 ]; then say "$1"; shift; "$@"; else say "would $1"; fi
}

if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  say "claude CLI not found; skipped"
  exit 0
fi
if [ -e "$SETTINGS" ] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS" 2>/dev/null; then
  say "$SETTINGS is not valid JSON; refusing to touch it" >&2
  exit 1
fi

changed=0
if [ ! -d "$MP/skills/impeccable" ]; then
  act "add the impeccable marketplace (pbakaus/impeccable)" \
    "$CLAUDE" plugin marketplace add pbakaus/impeccable || exit 1
  changed=1
fi

enabled="$(python3 -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get("enabledPlugins",{}).get(sys.argv[2]) is True)
except Exception: print(False)' "$SETTINGS" "$PLUGIN")"
if [ "$enabled" = True ]; then
  act "disable the $PLUGIN plugin (its hooks run on every edit)" \
    "$CLAUDE" plugin disable "$PLUGIN" --scope user || exit 1
  changed=1
fi

link() {  # link <target> <linkname>
  [ "$(readlink "$2" 2>/dev/null)" = "$1" ] && return 0
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    say "$2 exists and is not a link; refusing to replace it" >&2
    return 1
  fi
  act "link $2 -> $1" sh -c 'mkdir -p "$(dirname "$2")" && ln -sfn "$1" "$2"' _ "$1" "$2" || return 1
  changed=1
}
link "$MP/skills/impeccable" "$CH/skills/impeccable" || exit 1
for a in $AGENTS; do link "$MP/agents/$a.md" "$CH/agents/$a.md" || exit 1; done

want="IMPECCABLE_HOOK_DISABLED=1 IMPECCABLE_NO_TELEMETRY=1"
[ -n "$IMPECCABLE_CACHE_ROOT" ] && want="$want IMPECCABLE_HOME=$IMPECCABLE_CACHE_ROOT"
missing="$(python3 -c '
import json,sys
try: env=json.load(open(sys.argv[1])).get("env",{})
except Exception: env={}
print(" ".join(kv for kv in sys.argv[2:] if env.get(kv.split("=",1)[0])!=kv.split("=",1)[1]))' "$SETTINGS" $want)"
if [ -n "$missing" ]; then
  act "set settings env: $missing" python3 -c '
import json,os,sys
p=sys.argv[1]; d=json.load(open(p)) if os.path.exists(p) else {}
env=d.setdefault("env",{})
for kv in sys.argv[2:]:
    k,v=kv.split("=",1); env[k]=v
tmp=p+".tmp"; json.dump(d,open(tmp,"w"),indent=2); open(tmp,"a").write("\n"); os.replace(tmp,p)' "$SETTINGS" $missing || exit 1
  changed=1
fi

if [ "$changed" = 0 ]; then
  say "on-demand setup already in place; nothing to do"
elif [ "$WRITE" = 0 ]; then
  say "(dry run; pass --write to apply)"
fi
exit 0
