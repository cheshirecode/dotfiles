#!/usr/bin/env bash
# Install the worklog hooks into ~/.claude/settings.json so Claude Code
# runs them at the right lifecycle points, plus wire `core.hooksPath` so
# git fires bin/git-hooks/pre-commit on every commit in this clone.
#
#   Claude Code (PreCompact + SessionEnd):
#     - bin/autosave.sh        → uncommitted worklog edits land in git
#                                 before the compact summary / session ends.
#     - bin/compact-kernels.sh → one resume kernel per active task is dumped
#                                 to _worklog/.cache/compact-kernels.md so
#                                 the next session re-orients on one file.
#
#   Git pre-commit:
#     - bin/git-hooks/pre-commit → path-filtered lint + test gate per
#                                   docs/helpers.md § Pre-commit hook.
#
# Usage:
#   bin/install-hooks.sh              # dry-run (prints the merged settings)
#   bin/install-hooks.sh --write      # apply the change
#   bin/install-hooks.sh --uninstall  # remove the hooks (dry-run)
#   bin/install-hooks.sh --uninstall --write
#
# Idempotent: re-running --write is a no-op once the hooks are present.
# Only touches entries pointing at this repo's scripts.

set -euo pipefail

MODE="install"
WRITE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write)     WRITE=1 ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)
      sed -n '2,19p' "$0"
      exit 0
      ;;
    *) echo "install-hooks: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
REPO_ROOT="$(resolve_worklog_repo)" || exit 1
cd "$REPO_ROOT"
AUTOSAVE="$REPO_ROOT/bin/autosave.sh"
KERNELS="$REPO_ROOT/bin/compact-kernels.sh"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

for s in "$AUTOSAVE" "$KERNELS"; do
  if [[ ! -x "$s" ]]; then
    echo "install-hooks: $s not executable" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

python3 - "$SETTINGS" "$AUTOSAVE" "$KERNELS" "$MODE" "$WRITE" <<'PY'
import json, pathlib, sys

settings_path, autosave, kernels, mode, write_flag = sys.argv[1:6]
write = write_flag == "1"
p = pathlib.Path(settings_path)

try:
  data = json.loads(p.read_text() or "{}")
  if not isinstance(data, dict):
    raise ValueError(f"settings root is {type(data).__name__}, expected object")
except (json.JSONDecodeError, ValueError) as e:
  print(f"install-hooks: refuse to edit malformed settings at {settings_path}: {e}", file=sys.stderr)
  sys.exit(1)

EVENTS = ("PreCompact", "SessionEnd")
SCRIPTS = (autosave, kernels)
# Per-event flag for autosave so the commit trailer can distinguish what
# triggered the snapshot. kernels is event-agnostic — no flag.
AUTOSAVE_FLAGS = {"PreCompact": "--trigger=pre-compact", "SessionEnd": "--trigger=session-end"}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
  print(f"install-hooks: settings.hooks is {type(hooks).__name__}, expected object", file=sys.stderr)
  sys.exit(1)

def entry_matches_script(entry, script):
  # Match any entry whose command references the given script path, to stay
  # idempotent across `bash <path>` vs bare `<path>` invocation styles.
  if not isinstance(entry, dict):
    return False
  for h in entry.get("hooks", []) or []:
    if isinstance(h, dict) and h.get("type") == "command":
      if script in (h.get("command") or ""):
        return True
  return False

changed = False

for event in EVENTS:
  event_list = hooks.setdefault(event, [])
  if not isinstance(event_list, list):
    print(f"install-hooks: settings.hooks.{event} is not a list", file=sys.stderr)
    sys.exit(1)

  for script in SCRIPTS:
    present = any(entry_matches_script(e, script) for e in event_list)
    # Autosave gets a per-event --trigger flag; kernels is bare.
    if script == autosave:
      command = f"{script} {AUTOSAVE_FLAGS[event]}"
    else:
      command = script
    if mode == "install" and not present:
      event_list.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}],
      })
      changed = True
    elif mode == "uninstall" and present:
      event_list[:] = [e for e in event_list if not entry_matches_script(e, script)]
      changed = True

  if mode == "uninstall" and not event_list:
    hooks.pop(event, None)

rendered = json.dumps(data, indent=2) + "\n"

if not changed:
  print(f"install-hooks: no change needed ({mode}: hooks {'already' if mode == 'install' else 'not'} present)")
  sys.exit(0)

if write:
  p.write_text(rendered)
  print(f"install-hooks: {mode}ed worklog hooks (PreCompact + SessionEnd × autosave.sh + compact-kernels.sh)")
  print(f"install-hooks: wrote {settings_path}")
else:
  print(f"install-hooks: DRY RUN — would {mode} worklog hooks")
  print(f"install-hooks: proposed {settings_path} contents:")
  print(rendered, end="")
  print("install-hooks: re-run with --write to apply")
PY

# ---- git pre-commit hook --------------------------------------------------
# Wire `core.hooksPath = bin/git-hooks` so the versioned pre-commit script
# fires for everyone who runs install-hooks.sh on their clone. Idempotent.
CURRENT_HOOKS_PATH="$(git -C "$REPO_ROOT" config --get core.hooksPath || true)"
DESIRED="bin/git-hooks"

if [[ "$MODE" == "install" ]]; then
  if [[ "$CURRENT_HOOKS_PATH" == "$DESIRED" ]]; then
    echo "install-hooks: git core.hooksPath already $DESIRED (no change)"
  else
    if (( WRITE )); then
      git -C "$REPO_ROOT" config core.hooksPath "$DESIRED"
      echo "install-hooks: set git core.hooksPath = $DESIRED"
    else
      echo "install-hooks: DRY RUN — would set git core.hooksPath = $DESIRED (current: ${CURRENT_HOOKS_PATH:-<unset>})"
    fi
  fi
else
  if [[ "$CURRENT_HOOKS_PATH" == "$DESIRED" ]]; then
    if (( WRITE )); then
      git -C "$REPO_ROOT" config --unset core.hooksPath
      echo "install-hooks: unset git core.hooksPath"
    else
      echo "install-hooks: DRY RUN — would unset git core.hooksPath"
    fi
  fi
fi
