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
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
CURSOR_SKILLS_DIR="${CURSOR_SKILLS_DIR:-$HOME/.cursor/skills}"
CACHE_DIR="${CLAUDE_AGENT_CACHE:-$HOME/.agents/skills}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"
SKILL_ROOTS=("$SKILLS_DIR" "$AGENT_SKILLS_DIR" "$CURSOR_SKILLS_DIR" "$CACHE_DIR")

is_owned_skill_install() {
  local target="$1" source="$2"
  python3 - "$target" "$source" <<'PY'
import hashlib
import pathlib
import sys

SENTINEL = ".installed_from"
target = pathlib.Path(sys.argv[1])
source = pathlib.Path(sys.argv[2])

def tree_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative_path = path.relative_to(root).as_posix()
        if relative_path == SENTINEL:
            continue
        relative = relative_path.encode()
        if path.is_symlink():
            digest.update(b"L\0" + relative + b"\0" + path.readlink().as_posix().encode() + b"\0")
        elif path.is_file():
            digest.update(b"F\0" + relative + b"\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
        elif path.is_dir():
            digest.update(b"D\0" + relative + b"\0")
    return digest.hexdigest()

if target.is_symlink():
    try:
        raise SystemExit(0 if target.resolve(strict=True) == source.resolve(strict=True) else 1)
    except FileNotFoundError:
        raise SystemExit(1)

if not target.is_dir():
    raise SystemExit(1)
sentinel = target / SENTINEL
if not sentinel.is_file():
    raise SystemExit(1)
try:
    lines = sentinel.read_text().splitlines()
except OSError:
    raise SystemExit(1)
if not lines:
    raise SystemExit(1)
digest_lines = [line for line in lines[1:] if line.startswith("content-sha256:")]
if digest_lines:
    raise SystemExit(0 if digest_lines[-1].split(":", 1)[1] == tree_digest(target) else 1)
raise SystemExit(0 if tree_digest(target) == tree_digest(source) else 1)
PY
}

echo "uninstall: removing verified skill installs"
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    source="$REPO_ROOT/skills/$name"
    for skill_root in "${SKILL_ROOTS[@]}"; do
      target="$skill_root/$name"
      if is_owned_skill_install "$target" "$source"; then
        if [[ -L "$target" ]]; then
          echo "  unlink $target"; rm "$target"
        elif [[ -d "$target" ]]; then
          echo "  rmdir  $target"; rm -rf "$target"
        fi
      elif [[ -e "$target" || -L "$target" ]]; then
        echo "  preserve unowned skill install: $target" >&2
      fi
    done
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
