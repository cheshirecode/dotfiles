#!/usr/bin/env bash
# Install the worklog hooks into ~/.claude/settings.json so Claude Code
# runs them at the right lifecycle points, plus wire git so it fires
# bin/git-hooks/{pre-commit,commit-msg,post-commit} on every commit in
# this clone.
#
#   Claude Code (PreCompact + SessionEnd):
#     - bin/autosave.sh        → uncommitted worklog edits land in git
#                                 before the compact summary / session ends.
#     - bin/autosave-flush.sh  → SessionEnd only: push debounced autosaves.
#     - bin/compact-kernels.sh → one resume kernel per active task is dumped
#                                 to _worklog/.cache/compact-kernels.md so
#                                 the next session re-orients on one file.
#
#   Git hooks:
#     - bin/git-hooks/pre-commit → path-filtered lint + test gate per
#                                   docs/helpers.md § Pre-commit hook.
#
#     Wiring mode depends on whether an OUTER core.hooksPath (system or
#     global scope) is already set:
#
#       - Outer hooksPath present → CHAIN. Some platforms (e.g. Coder)
#         ship their own system-level core.hooksPath pointing at a
#         blocking secret scanner (gitleaks) whose pre-commit sources
#         run_existing_hook.sh, which in turn execs the repo's own
#         .git/hooks/<name> if present. We symlink our hooks into
#         .git/hooks/ so BOTH the platform scanner and the worklog
#         hooks run. We deliberately do NOT set a repo-local
#         core.hooksPath in this case: git only ever honors one
#         hooksPath, so a repo-local value would silently make git
#         ignore the outer path — and whatever it runs — for this
#         clone (verified: this disabled gitleaks entirely on a clone
#         until reverted by hand). Overriding core.hooksPath is only
#         safe when nothing outer is already relying on it.
#
#       - No outer hooksPath → FALLBACK. Set repo-local core.hooksPath
#         to the skill's git-hooks dir directly (the old, simpler
#         behavior) since there's nothing else to preserve.
#
# Usage:
#   install-hooks.sh                                  # dry-run for cwd / $WORKLOG_REPO
#   install-hooks.sh --write                          # apply
#   install-hooks.sh --data-root=<path>               # dry-run for a specific clone
#   install-hooks.sh --data-root=<path> --write       # apply to that clone
#   install-hooks.sh --uninstall [--data-root=<path>] [--write]
#   install-hooks.sh --data-root=<path> --write --git-hooks-only   # skip settings.json
#
# Guard: --write refuses to touch the DEFAULT ~/.claude/settings.json when the
# target repo is temporary / not a worklog repo, or when running from a copy of
# this script other than the installed skill. Both bake a path into every
# session's hooks that later vanishes. Override with CLAUDE_SETTINGS=<path>.
#
# Idempotent: re-running --write is a no-op once the hooks are present.
# Only touches entries pointing at the skill's scripts, and --uninstall
# reverses whichever mode (chain symlinks, or repo-local hooksPath) is
# currently active.

set -euo pipefail

MODE="install"
WRITE=0
DATA_ROOT_OVERRIDE=""
GIT_HOOKS_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write)         WRITE=1 ;;
    --uninstall)     MODE="uninstall" ;;
    --data-root=*)   DATA_ROOT_OVERRIDE="${1#--data-root=}" ;;
    --git-hooks-only) GIT_HOOKS_ONLY=1 ;;
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
FLUSH="$SCRIPT_DIR/autosave-flush.sh"
KERNELS="$SCRIPT_DIR/compact-kernels.sh"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
SETTINGS_IS_DEFAULT=0
[[ -z "${CLAUDE_SETTINGS:-}" ]] && SETTINGS_IS_DEFAULT=1

# Guard the global write. `--data-root` reads as "operate on this repo", but the
# Claude-hooks half of this script edits ONE global settings file and bakes
# REPO_ROOT into every hook command. Point it at a scratch repo and the live
# hooks of every session on this machine are silently repointed there; when the
# scratch dir is later removed, autosave and compact-kernels fail on every
# compaction. The scripts themselves exit 1 loudly, but a hook's stderr is not
# surfaced, so five broken hooks look like nothing at all. This bit two sessions
# on 2026-08-28.
#
# So: a target that is not a durable worklog repo may configure git hooks, but
# may not rewrite the DEFAULT settings file. Set CLAUDE_SETTINGS to a scratch
# path to exercise the Claude-hooks half in a test.
if (( WRITE )) && (( SETTINGS_IS_DEFAULT )) && ! (( GIT_HOOKS_ONLY )); then
  reason=""
  case "$REPO_ROOT" in
    /tmp/*|/var/tmp/*|"${TMPDIR:-/nonexistent}"/*) reason="a temporary directory" ;;
  esac
  [[ -z "$reason" && ! -d "$REPO_ROOT/people" ]] \
    && reason="not a worklog data repo (no people/ directory)"

  # Second axis: WHICH COPY of this script is running. The hook commands embed
  # $SCRIPT_DIR, so invoking a worktree or scratch copy bakes that path into the
  # global settings — and it disappears when the worktree is removed. Same
  # silent breakage, different cause, so it needs its own check.
  if [[ -z "$reason" ]]; then
    installed="$(readlink -f "$HOME/.claude/skills/worklog/bin" 2>/dev/null || true)"
    here="$(readlink -f "$SCRIPT_DIR")"
    [[ -n "$installed" && "$here" != "$installed" ]] \
      && reason="running from $here, not the installed skill ($installed)"
  fi
  if [[ -n "$reason" ]]; then
    cat >&2 <<EOF
install-hooks: refusing to rewrite $SETTINGS
  target repo : $REPO_ROOT
  reason      : $reason

  Hook commands bake this path in as WORKLOG_REPO, so writing it to the global
  settings file would repoint every session's hooks at a path that cannot work.

  To exercise the Claude-hooks half against this target, redirect the write:
    CLAUDE_SETTINGS="\$(mktemp)" $0 --data-root="$REPO_ROOT" --write
  Git hooks for this repo can be installed on their own with:
    $0 --data-root="$REPO_ROOT" --write --git-hooks-only
EOF
    exit 1
  fi
fi

for s in "$AUTOSAVE" "$FLUSH" "$KERNELS"; do
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

if (( GIT_HOOKS_ONLY )); then
  echo "install-hooks: --git-hooks-only, leaving $SETTINGS untouched"
else
python3 - "$SETTINGS" "$AUTOSAVE" "$FLUSH" "$KERNELS" "$MODE" "$WRITE" "$REPO_ROOT" "$WORKLOG_LDAP_FROM_ENVRC" <<'PY'
import json, pathlib, sys

settings_path, autosave, flush, kernels, mode, write_flag, repo_root, worklog_ldap = sys.argv[1:9]
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
# SessionEnd adds autosave-flush after kernels to push debounced autosaves.
SCRIPTS_BY_EVENT = {
  "PreCompact": (autosave, kernels),
  "SessionEnd": (autosave, kernels, flush),
}
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
    if "autosave.sh" in cmd or "autosave-flush.sh" in cmd or "compact-kernels.sh" in cmd:
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
    for script in SCRIPTS_BY_EVENT[event]:
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
  print(f"install-hooks: {mode}ed worklog hooks (PreCompact + SessionEnd × autosave + compact-kernels + flush)")
  print(f"install-hooks: wrote {settings_path}")
else:
  print(f"install-hooks: DRY RUN — would {mode} worklog hooks")
  print(f"install-hooks: proposed {settings_path} contents:")
  print(rendered, end="")
  print("install-hooks: re-run with --write to apply")
PY
fi

# ---- git hooks -------------------------------------------------------------
# Absolute path is the only sane option post-relocation — the hooks live
# in dotfiles, not in the data repo. Per-machine brittle (path differs
# per host); --data-root callers re-run install-hooks.sh per machine to
# refresh.
DESIRED="$SCRIPT_DIR/git-hooks"
HOOK_NAMES=(pre-commit commit-msg post-commit)

# Outer scope = system or global core.hooksPath — anything NOT set by us
# in this repo's local config. System takes precedence, matching git's
# own resolution order.
OUTER_HOOKS_PATH="$(git -C "$REPO_ROOT" config --system --get core.hooksPath 2>/dev/null || true)"
if [[ -z "$OUTER_HOOKS_PATH" ]]; then
  OUTER_HOOKS_PATH="$(git -C "$REPO_ROOT" config --global --get core.hooksPath 2>/dev/null || true)"
fi
LOCAL_HOOKS_PATH="$(git -C "$REPO_ROOT" config --local --get core.hooksPath 2>/dev/null || true)"
# NOTE: `git rev-parse --git-path hooks` resolves core.hooksPath itself,
# so it can't be used here — it would just echo back whatever hooksPath
# is already configured. We want the real on-disk .git/hooks/ directory
# regardless of hooksPath, so derive it from --git-dir instead.
GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --git-dir)"
[[ "$GIT_DIR" == /* ]] || GIT_DIR="$REPO_ROOT/$GIT_DIR"
GIT_HOOKS_DIR="$GIT_DIR/hooks"

# Treat an outer hooksPath equal to our own DESIRED (e.g. set by an old
# run of this very script, or a --data-root sharing config) as "no outer
# hooksPath to preserve" — there's nothing else to chain with.
if [[ "$OUTER_HOOKS_PATH" == "$DESIRED" ]]; then
  OUTER_HOOKS_PATH=""
fi

symlink_current_target() {
  # Prints the resolved link target of .git/hooks/<name>, or nothing.
  # Always returns 0 — this is used in `current="$(...)"` assignments
  # under `set -e`, where a nonzero substitution exit would abort the
  # script even though "not a symlink" is an expected, handled case.
  if [[ -L "$GIT_HOOKS_DIR/$1" ]]; then
    readlink "$GIT_HOOKS_DIR/$1"
  fi
  return 0
}

if [[ "$MODE" == "install" ]]; then
  if [[ -n "$OUTER_HOOKS_PATH" ]]; then
    # ---- CHAIN mode: symlink into .git/hooks/, leave outer hooksPath alone.
    changed=0

    if [[ -n "$LOCAL_HOOKS_PATH" && "$LOCAL_HOOKS_PATH" == "$DESIRED" ]]; then
      # Leftover repo-local override from a previous (unsafe) run — it
      # would shadow the outer hooksPath, so it must go.
      if (( WRITE )); then
        git -C "$REPO_ROOT" config --unset core.hooksPath
        echo "install-hooks: unset repo-local core.hooksPath (was shadowing outer $OUTER_HOOKS_PATH)"
      else
        echo "install-hooks: DRY RUN — would unset repo-local core.hooksPath (shadows outer $OUTER_HOOKS_PATH)"
      fi
      changed=1
    fi

    (( WRITE )) && mkdir -p "$GIT_HOOKS_DIR"

    for h in "${HOOK_NAMES[@]}"; do
      target="$DESIRED/$h"
      dest="$GIT_HOOKS_DIR/$h"
      current="$(symlink_current_target "$h")"
      if [[ "$current" == "$target" ]]; then
        continue
      fi
      if [[ -e "$dest" && ! -L "$dest" ]]; then
        echo "install-hooks: $dest exists and is not a symlink — leaving it untouched (worklog $h hook not chained)" >&2
        continue
      fi
      changed=1
      if (( WRITE )); then
        ln -sf "$target" "$dest"
        echo "install-hooks: chained $dest -> $target"
      else
        echo "install-hooks: DRY RUN — would chain $dest -> $target (current: ${current:-<none>})"
      fi
    done

    if (( ! changed )); then
      echo "install-hooks: git hooks already chained via $GIT_HOOKS_DIR (outer hooksPath: $OUTER_HOOKS_PATH; no change)"
    fi
  else
    # ---- FALLBACK mode: no outer hooksPath to preserve — safe to own it.
    # Clean up any stale chain symlinks first so state doesn't straddle
    # both modes.
    for h in "${HOOK_NAMES[@]}"; do
      dest="$GIT_HOOKS_DIR/$h"
      current="$(symlink_current_target "$h")"
      if [[ "$current" == "$DESIRED/$h" ]]; then
        if (( WRITE )); then
          rm -f "$dest"
          echo "install-hooks: removed stale chain symlink $dest"
        else
          echo "install-hooks: DRY RUN — would remove stale chain symlink $dest"
        fi
      fi
    done

    if [[ "$LOCAL_HOOKS_PATH" == "$DESIRED" ]]; then
      echo "install-hooks: git core.hooksPath already $DESIRED (no change)"
    else
      if (( WRITE )); then
        git -C "$REPO_ROOT" config core.hooksPath "$DESIRED"
        echo "install-hooks: set git core.hooksPath = $DESIRED"
      else
        echo "install-hooks: DRY RUN — would set git core.hooksPath = $DESIRED (current: ${LOCAL_HOOKS_PATH:-<unset>})"
      fi
    fi
  fi
else
  # ---- uninstall: reverse whichever mode is actually active, regardless
  # of what the outer config currently says (it may have changed since
  # install).
  if [[ "$LOCAL_HOOKS_PATH" == "$DESIRED" ]]; then
    if (( WRITE )); then
      git -C "$REPO_ROOT" config --unset core.hooksPath
      echo "install-hooks: unset git core.hooksPath"
    else
      echo "install-hooks: DRY RUN — would unset git core.hooksPath"
    fi
  fi

  for h in "${HOOK_NAMES[@]}"; do
    dest="$GIT_HOOKS_DIR/$h"
    current="$(symlink_current_target "$h")"
    if [[ "$current" == "$DESIRED/$h" ]]; then
      if (( WRITE )); then
        rm -f "$dest"
        echo "install-hooks: removed chain symlink $dest"
      else
        echo "install-hooks: DRY RUN — would remove chain symlink $dest"
      fi
    fi
  done
fi
