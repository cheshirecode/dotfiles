#!/usr/bin/env bash
# Bootstrap a fresh worklog data repo from the skill's templates/.
#
# Usage:
#   init-new-data-repo.sh <path> [<ldap>]
#
# What it does (idempotent — safe to re-run):
#   1. Resolves LDAP (arg → $WORKLOG_LDAP → git email → $USER).
#   2. mkdir + git init at <path> if not already a repo.
#   3. Copies templates/{AGENTS.md,README.md,CLAUDE.md,.gitignore,.yamllint,
#      .dockerignore,docs/*.md} verbatim — they already use `<ldap>` placeholder,
#      no substitution needed.
#   4. Creates people/<ldap>/{active,archive}/ with .gitkeep stubs.
#   5. Writes .envrc with WORKLOG_REPO=$PWD (+ WORKLOG_LDAP if arg-supplied).
#   6. Initial commit (if the repo is empty).
#   7. Wires hooks via install-hooks.sh --data-root=<path>.
#
# What it deliberately does NOT do:
#   - Create a remote (you do `gh repo create` separately).
#   - Push (you do `git push` separately).
#   - Copy bin/ — bin/ is in the skill, not the data repo. The fresh repo
#     gets only the tombstone via the .gitignore (bin/ stays empty until
#     bin/README.md is added by you or a subsequent operation).
#
# Idempotency: every step is "skip if exists" or "additive append". Re-running
# on an existing data repo updates templates but never destroys people/* data.

set -euo pipefail

usage() {
  cat >&2 <<USAGE
usage: init-new-data-repo.sh <path> [<ldap>]

Bootstrap a fresh worklog data repo at <path> using the skill's templates.

Args:
  <path>   Target directory (created if missing).
  <ldap>   Identity for this clone (optional; resolves via the same chain
           as bin/_lib.sh::resolve_ldap if omitted).

Examples:
  init-new-data-repo.sh ~/Documents/projects/_worklog            # implicit ldap
  init-new-data-repo.sh ~/Documents/projects/_worklog fredtran   # explicit
USAGE
  exit "${1:-2}"
}

[[ $# -lt 1 || $# -gt 2 ]] && usage 2
TARGET="$1"
ARG_LDAP="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES="$SKILL_DIR/templates"

[[ -d "$TEMPLATES" ]] || { echo "init-new-data-repo: missing $TEMPLATES" >&2; exit 1; }

# Resolve LDAP. Don't source _lib.sh (it requires WORKLOG_REPO); duplicate
# the small chain inline.
LDAP="$ARG_LDAP"
[[ -z "$LDAP" ]] && LDAP="${WORKLOG_LDAP:-}"
[[ -z "$LDAP" ]] && LDAP="$(git config user.email 2>/dev/null | sed -E 's|^[0-9]+\+||; s|@.*||' || true)"
[[ -z "$LDAP" ]] && LDAP="${USER:-user}"
echo "init-new-data-repo: LDAP=$LDAP TARGET=$TARGET"

# 1. mkdir + git init
mkdir -p "$TARGET"
cd "$TARGET"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init -b main -q
  echo "  git init (main branch)"
else
  echo "  git repo already initialized"
fi

# 2. Copy verbatim templates (top-level)
for f in AGENTS.md README.md CLAUDE.md .gitignore .yamllint .dockerignore; do
  src="$TEMPLATES/$f"
  if [[ -f "$src" && ! -f "$f" ]]; then
    cp "$src" "$f"
    echo "  + $f (from template)"
  elif [[ -f "$f" ]]; then
    echo "  = $f (kept existing)"
  fi
done

# 3. Copy docs/ (skip if any already exist — additive)
if [[ ! -d docs ]]; then
  mkdir -p docs
  cp -R "$TEMPLATES/docs/." docs/
  echo "  + docs/ (from template — $(ls docs/ | wc -l | tr -d ' ') files)"
else
  echo "  = docs/ (kept existing)"
fi

# 4. People namespace
mkdir -p "people/$LDAP/active" "people/$LDAP/archive"
[[ -f "people/$LDAP/active/.gitkeep" ]]  || touch "people/$LDAP/active/.gitkeep"
[[ -f "people/$LDAP/archive/.gitkeep" ]] || touch "people/$LDAP/archive/.gitkeep"
echo "  = people/$LDAP/{active,archive}/ (stubs in place)"

# 4b. bin/ tombstone — protocol scripts live in the dotfiles skill, not here.
# The README is the only file ever committed under bin/; the pre-commit guard
# in the skill's git-hooks rejects any other staged bin/* addition.
mkdir -p bin
if [[ ! -f bin/README.md ]]; then
  cat > bin/README.md <<TOMBSTONE
# bin/ moved to dotfiles skill

Worklog protocol scripts live at:

    ~/Documents/oss/dotfiles/skills/worklog/bin/

Invoke via the \`\$WORKLOG_BIN\` env var (set by the per-clone \`.envrc\`).

Bootstrap a fresh data repo:

    "\$WORKLOG_BIN/init-new-data-repo.sh" <path> [<ldap>]
TOMBSTONE
  echo "  + bin/README.md (tombstone)"
fi

# 5. .envrc (only if missing — never overwrite existing customization)
if [[ ! -f .envrc ]]; then
  {
    printf 'export WORKLOG_REPO="$PWD"\n'
    [[ -n "$ARG_LDAP" ]] && printf 'export WORKLOG_LDAP=%s\n' "$ARG_LDAP"
  } > .envrc
  echo "  + .envrc (run \`direnv allow\` here to activate)"
fi

# 6. Initial commit if repo has no commits yet
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git add -A
  git -c commit.gpgsign=false commit -q -m "Bootstrap worklog data repo for $LDAP

Seeded from skill templates at $SKILL_DIR/templates/.
Scripts live in $SCRIPT_DIR (the dotfiles skill bin/ — SoT).

Next steps:
  direnv allow                                     # activate .envrc
  $SCRIPT_DIR/install-hooks.sh --data-root=$TARGET # wire git + Claude hooks
  gh repo create <owner>/<repo> --private          # if you want a remote
  git push -u origin main"
  echo "  + initial commit"
fi

# 7. Wire hooks (delegated — separate concern)
if [[ -x "$SCRIPT_DIR/install-hooks.sh" ]]; then
  echo "  hook wiring (delegated to install-hooks.sh; pass --write to apply):"
  echo "    $SCRIPT_DIR/install-hooks.sh --data-root=$TARGET --write"
fi

echo
echo "init-new-data-repo: done. cd $TARGET && direnv allow"
