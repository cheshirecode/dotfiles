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
#   install-hooks.sh                                  # dry-run for cwd / $WORKLOG_REPO
#   install-hooks.sh --write                          # apply
#   install-hooks.sh --data-root=<path>               # dry-run for a specific clone
#   install-hooks.sh --data-root=<path> --write       # apply to that clone
#   install-hooks.sh --uninstall [--data-root=<path>] [--write]
#
# Idempotent: re-running --write is a no-op once the hooks are present.
# Only touches entries pointing at the skill's scripts.

set -euo pipefail

MODE="install"
WRITE=0
DATA_ROOT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write)         WRITE=1 ;;
    --uninstall)     MODE="uninstall" ;;
    --data-root=*)   DATA_ROOT_OVERRIDE="${1#--data-root=}" ;;
    -h|--help)
      sed -n '2,23p' "$0"
      exit 0
      ;;
    *) echo "install-hooks: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
# --data-root overrides WORKLOG_REPO env / cwd-walk
if [[ -n "$DATA_ROOT_OVERRIDE" ]]; then
  [[ -d "$DATA_ROOT_OVERRIDE/.git" || -f "$DATA_ROOT_OVERRIDE/.git" ]] \
    || { echo "install-hooks: --data-root=$DATA_ROOT_OVERRIDE is not a git repo" >&2; exit 1; }
  REPO_ROOT="$(cd "$DATA_ROOT_OVERRIDE" && pwd)"
else
  REPO_ROOT="$(resolve_worklog_repo)" || exit 1
fi
cd "$REPO_ROOT"
# Scripts live in the skill (this dir), not in the data repo's bin/
AUTOSAVE="$SCRIPT_DIR/autosave.sh"
KERNELS="$SCRIPT_DIR/compact-kernels.sh"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

for s in "$AUTOSAVE" "$KERNELS"; do
  if [[ ! -x "$s" ]]; then
    echo "install-hooks: $s not executable" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

# Hooks run outside direnv — pin the data repo (and optional LDAP) inline.
WORKLOG_LDAP_FROM_ENVRC=""
if [[ -f "$REPO_ROOT/.envrc" ]]; then
  WORKLOG_LDAP_FROM_ENVRC="$(
    grep -E '^export WORKLOG_LDAP=' "$REPO_ROOT/.envrc" 2>/dev/null \
      | sed -E 's/^export WORKLOG_LDAP=//' | tr -d '"' || true
  )"
fi

python3 - "$SETTINGS" "$AUTOSAVE" "$KERNELS" "$MODE" "$WRITE" "$REPO_ROOT" "$WORKLOG_LDAP_FROM_ENVRC" <<'PY'
import json, pathlib, sys

settings_path, autosave, kernels, mode, write_flag, repo_root, worklog_ldap = sys.argv[1:8]
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

def entry_references_worklog_script(entry):
  # Match autosave/compact-kernels hooks — current skill path or legacy
  # _worklog/bin/ tombstone era — so reinstall migrates stale entries.
  if not isinstance(entry, dict):
    return False
  for h in entry.get("hooks", []) or []:
    if not isinstance(h, dict) or h.get("type") != "command":
      continue
    cmd = h.get("command") or ""
    if "autosave.sh" in cmd or "compact-kernels.sh" in cmd:
      return True
  return False


def build_command(script, event):
  env_parts = [f'WORKLOG_REPO="{repo_root}"']
  if worklog_ldap:
    env_parts.append(f'WORKLOG_LDAP="{worklog_ldap}"')
  env = " ".join(env_parts)
  if script == autosave:
    return f"{env} {script} {AUTOSAVE_FLAGS[event]}"
  return f"{env} {script}"

changed = False

for event in EVENTS:
  event_list = hooks.setdefault(event, [])
  if not isinstance(event_list, list):
    print(f"install-hooks: settings.hooks.{event} is not a list", file=sys.stderr)
    sys.exit(1)

  if mode == "install":
    before = len(event_list)
    event_list[:] = [e for e in event_list if not entry_references_worklog_script(e)]
    if len(event_list) != before:
      changed = True
    desired = []
    for script in SCRIPTS:
      desired.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": build_command(script, event)}],
      })
    for entry in desired:
      cmd = entry["hooks"][0]["command"]
      if not any(
        isinstance(e, dict)
        and any(
          isinstance(h, dict) and h.get("type") == "command" and h.get("command") == cmd
          for h in (e.get("hooks") or [])
        )
        for e in event_list
      ):
        event_list.append(entry)
        changed = True
  else:
    before = len(event_list)
    event_list[:] = [e for e in event_list if not entry_references_worklog_script(e)]
    if len(event_list) != before:
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
# Wire `core.hooksPath` to the skill's git-hooks dir. Absolute path is the
# only sane option post-relocation — the hooks live in dotfiles, not in
# the data repo. Per-machine brittle (path differs per host); --data-root
# callers re-run install-hooks.sh per machine to refresh.
CURRENT_HOOKS_PATH="$(git -C "$REPO_ROOT" config --get core.hooksPath || true)"
DESIRED="$SCRIPT_DIR/git-hooks"

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
