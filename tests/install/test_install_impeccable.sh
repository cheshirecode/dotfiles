#!/usr/bin/env bash
# bin/install-impeccable.sh: make impeccable available on demand with no hooks.
# The plugin must never end up enabled (its hooks run a downloaded engine on
# every edit in every session), the skill and three agents are linked as
# user-level files, settings `env` is merged without touching other keys, and
# a second run changes nothing. A stub `claude` records calls and simulates
# the marketplace clone; no network.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd -P)"
SCRIPT="$REPO/bin/install-impeccable.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-impeccable.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
note() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$TMP/calls"
CH="\$CLAUDE_HOME"; MP="\$CH/plugins/marketplaces/impeccable/plugin"
case "\$*" in
  "plugin marketplace add pbakaus/impeccable")
    mkdir -p "\$MP/skills/impeccable/scripts" "\$MP/agents"
    echo "name: impeccable" > "\$MP/skills/impeccable/SKILL.md"
    for a in impeccable-documenter impeccable-finish-reviewer impeccable-manual-edit-applier impeccable-asset-producer; do
      echo "name: \$a" > "\$MP/agents/\$a.md"; done ;;
  "plugin disable impeccable@impeccable --scope user")
    python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d.setdefault("enabledPlugins",{})["impeccable@impeccable"]=False;json.dump(d,open(p,"w"))' "\$CH/settings.json" ;;
  *) exit 9 ;;
esac
STUB
chmod +x "$TMP/bin/claude"

fresh() {  # fresh <name> -> sets CH with a settings.json holding unrelated keys
  CH="$TMP/$1/.claude"; mkdir -p "$CH"; : > "$TMP/calls"
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"x"}]}]},"env":{"OTHER":"keep"},"tui":"default"}\n' > "$CH/settings.json"
}
run() {  # run [args...] -> OUT, RC
  OUT=$(env -i PATH="$TMP/bin:$PATH" HOME="$TMP/home" CLAUDE_HOME="$CH" \
        IMPECCABLE_CACHE_ROOT="${CACHE-/persist/.impeccable}" bash "$SCRIPT" "$@" 2>&1); RC=$?
}
envv() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("env",{}).get(sys.argv[2],"<unset>"))' "$CH/settings.json" "$1"; }

# 1. Fresh machine: clone, link, merge env; never install or enable the plugin.
fresh a; run --write
[ "$RC" = 0 ] || note "fresh run exited $RC: $OUT"
grep -qx 'plugin marketplace add pbakaus/impeccable' "$TMP/calls" || note "marketplace was not added"
grep -q 'plugin install' "$TMP/calls" && note "the plugin was INSTALLED; its hooks would be one toggle away"
[ "$(readlink "$CH/skills/impeccable")" = "$CH/plugins/marketplaces/impeccable/plugin/skills/impeccable" ] || note "skill not linked"
for a in impeccable-documenter impeccable-finish-reviewer impeccable-manual-edit-applier; do
  [ -L "$CH/agents/$a.md" ] || note "agent $a not linked"; done
[ -e "$CH/agents/impeccable-asset-producer.md" ] && note "linked asset-producer, which needs CLAUDE_PLUGIN_ROOT"
[ "$(envv IMPECCABLE_HOOK_DISABLED)" = 1 ] || note "IMPECCABLE_HOOK_DISABLED not set"
[ "$(envv IMPECCABLE_NO_TELEMETRY)" = 1 ] || note "IMPECCABLE_NO_TELEMETRY not set"
[ "$(envv IMPECCABLE_HOME)" = /persist/.impeccable ] || note "IMPECCABLE_HOME not set to the cache root"
[ "$(envv OTHER)" = keep ] || note "an unrelated env key was lost"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["tui"]=="default" and d["hooks"]["SessionStart"]' "$CH/settings.json" \
  || note "unrelated settings keys were lost"

# 2. Second run: no calls, nothing to do.
: > "$TMP/calls"; run --write
[ -s "$TMP/calls" ] && note "second run called claude: $(cat "$TMP/calls")"
grep -q 'nothing to do' <<<"$OUT" || note "second run did not report nothing to do: $OUT"

# 3. A machine where the plugin is ENABLED gets it disabled.
fresh b; python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["enabledPlugins"]={"impeccable@impeccable":True};json.dump(d,open(p,"w"))' "$CH/settings.json"
run --write
grep -qx 'plugin disable impeccable@impeccable --scope user' "$TMP/calls" || note "an enabled plugin was not disabled"
python3 -c 'import json,sys;assert json.load(open(sys.argv[1]))["enabledPlugins"]["impeccable@impeccable"] is False' "$CH/settings.json" \
  || note "plugin still enabled after the run"

# 4. Dry run changes nothing.
fresh c; cp "$CH/settings.json" "$TMP/c.before"; run
cmp -s "$CH/settings.json" "$TMP/c.before" || note "dry run modified settings.json"
[ -e "$CH/skills/impeccable" ] && note "dry run created the skill link"
[ -s "$TMP/calls" ] && note "dry run called claude: $(cat "$TMP/calls")"

# 5. Malformed settings.json is refused, not overwritten.
fresh d; printf '{"broken": ' > "$CH/settings.json"; run --write
[ "$RC" = 1 ] || note "malformed settings: exit $RC, want 1"
[ "$(cat "$CH/settings.json")" = '{"broken": ' ] || note "malformed settings.json was rewritten"
[ -e "$CH/skills/impeccable" ] && note "malformed settings: still linked the skill (refuse before any change)"
[ -s "$TMP/calls" ] && note "malformed settings: still called claude"

# 6. A real directory where the skill link goes is refused, not replaced.
fresh e; mkdir -p "$CH/skills/impeccable"; echo mine > "$CH/skills/impeccable/SKILL.md"; run --write
[ "$RC" = 1 ] || note "existing skill dir: exit $RC, want 1"
[ "$(cat "$CH/skills/impeccable/SKILL.md")" = mine ] || note "an existing skill directory was replaced"

# 7. No persistent cache root: IMPECCABLE_HOME stays unset.
fresh f; CACHE="" run --write
[ "$(envv IMPECCABLE_HOME)" = "<unset>" ] || note "IMPECCABLE_HOME set without a cache root"

# 8. No claude CLI: skipped, exit 0.
fresh g; OUT=$(env -i PATH=/usr/bin:/bin HOME="$TMP/home" CLAUDE_HOME="$CH" CLAUDE_BIN=no-such-claude bash "$SCRIPT" --write 2>&1); RC=$?
[ "$RC" = 0 ] && grep -q 'not found; skipped' <<<"$OUT" || note "missing claude CLI: rc=$RC out=$OUT"

[ "$fails" -eq 0 ] || exit 1
echo "ok: impeccable is set up on demand with no plugin hooks, merges settings safely, and is idempotent"
