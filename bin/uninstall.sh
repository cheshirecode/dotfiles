#!/usr/bin/env bash
# Remove what bin/install.sh added. Preserves:
#   - your worklog content (people/<ldap>/*.md never touched)
#   - your shell rc files (we didn't modify them)
#   - runtime packages (python3, gh, etc. — uninstall those yourself)
#
# Removes:
#   - symlinks/copies in ~/.claude/skills/ for skills listed in manifest
#   - vendored clones in ~/.agents/skills/
#   - PreCompact/SessionEnd hooks in ~/.claude/settings.json (delegated to the
#     worklog repo's own uninstall-hooks.sh if present; otherwise warns)
#
# By default does NOT delete $PROJECTS_DIR/_worklog (your journal).
# Pass --purge-worklog to delete it (asks for confirmation).
#
# Idempotent.

set -uo pipefail

PURGE_WORKLOG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-worklog) PURGE_WORKLOG=1 ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "uninstall: unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest/skills.yaml"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CACHE_DIR="${CLAUDE_AGENT_CACHE:-$HOME/.agents/skills}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"

echo "uninstall: removing skill installs from $SKILLS_DIR"
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    target="$SKILLS_DIR/$name"
    if [[ -L "$target" ]]; then
      echo "  unlink $target"; rm "$target"
    elif [[ -d "$target" ]]; then
      echo "  rmdir  $target"; rm -rf "$target"
    fi
    cache="$CACHE_DIR/$name"
    if [[ -d "$cache" ]]; then
      echo "  rmdir  $cache"; rm -rf "$cache"
    fi
  done < <(python3 -c "import yaml; print('\n'.join(s['name'] for s in yaml.safe_load(open('$MANIFEST'))['skills']))" 2>/dev/null)
fi

# Hooks — delegate to worklog repo's own uninstaller if it exists.
hook_remover="$PROJECTS_DIR/_worklog/bin/install-hooks.sh"
if [[ -x "$hook_remover" ]] && "$hook_remover" --help 2>&1 | grep -q -- --remove; then
  echo "uninstall: removing worklog hooks"
  "$hook_remover" --remove || echo "uninstall: WARN — hook removal exited non-zero"
else
  echo "uninstall: hook removal not delegated (no --remove flag on install-hooks.sh)."
  echo "uninstall: edit ~/.claude/settings.json by hand if you want hooks gone."
fi

if [[ $PURGE_WORKLOG -eq 1 ]]; then
  if [[ -d "$PROJECTS_DIR/_worklog" ]]; then
    read -r -p "uninstall: PERMANENTLY delete $PROJECTS_DIR/_worklog? [y/N] " ans
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      rm -rf "$PROJECTS_DIR/_worklog"
      echo "uninstall: worklog removed"
    else
      echo "uninstall: worklog kept"
    fi
  fi
fi

echo "uninstall: done"
