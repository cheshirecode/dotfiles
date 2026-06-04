#!/usr/bin/env bash
# Post-install assertion. Returns non-zero if anything's broken.
#
# Checks (in order):
#   1. Runtime deps on PATH (python3, gh, git, rg, jq, direnv)
#   2. Python ≥ 3.10 (worklog lint helpers depend on 3.10+ syntax)
#   3. PyYAML importable (install-skills.sh uses it)
#   4. Each manifest skill present as a SKILL.md under ~/.claude/skills/
#   5. _worklog repo present and on a clean HEAD
#   6. Hooks wired (.claude/settings.json mentions autosave)
#   7. gh auth (warn-only — works for unauth'd public-repo flows)

set -uo pipefail  # no -e: we collect all failures, exit non-zero at the end

FAIL=0
WARN=0
say()  { printf "  %-7s %s\n" "$1" "$2"; }
ok()   { say "OK"   "$1"; }
fail() { say "FAIL" "$1"; FAIL=$((FAIL+1)); }
warn() { say "WARN" "$1"; WARN=$((WARN+1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest/skills.yaml"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"

echo "doctor: runtime deps"
for tool in python3 gh git rg jq direnv; do
  command -v "$tool" >/dev/null && ok "$tool $(command -v $tool)" || fail "$tool not on PATH"
done

echo "doctor: python"
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
  ok "python3 $(python3 -V 2>&1 | awk '{print $2}') ≥ 3.10"
else
  fail "python3 older than 3.10"
fi
python3 -c 'import yaml' 2>/dev/null && ok "PyYAML importable" || fail "PyYAML not installed (pip3 install --user pyyaml)"

echo "doctor: skills"
if [[ -f "$MANIFEST" ]]; then
  # Validation moved to install-skills.sh (council item #3 — install-time is
  # the right layer). Doctor just confirms presence here.
  # Skill-list error capture: a broken manifest used to silently produce an
  # empty list which passed the loop with "0 failures". Now: stderr captured,
  # empty-result-with-stderr = FAIL.
  skill_list_err=$(mktemp)
  skill_list=$(python3 -c "
import yaml
print('\n'.join(s['name'] for s in yaml.safe_load(open('$MANIFEST'))['skills']))
" 2>"$skill_list_err")
  if [[ -z "$skill_list" ]] && [[ -s "$skill_list_err" ]]; then
    fail "manifest parse error: $(cat "$skill_list_err")"
  fi
  rm -f "$skill_list_err"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    skill_md="$SKILLS_DIR/$name/SKILL.md"
    if [[ -f "$skill_md" ]]; then
      ok "$name → $skill_md"
    else
      warn "$name SKILL.md missing (run bin/install-skills.sh)"
    fi
  done <<< "$skill_list"
else
  fail "manifest/skills.yaml missing"
fi

echo "doctor: worklog"
if [[ -d "$PROJECTS_DIR/_worklog/.git" ]]; then
  ok "_worklog cloned at $PROJECTS_DIR/_worklog"
  if [[ -z "$(git -C "$PROJECTS_DIR/_worklog" status --porcelain 2>/dev/null)" ]]; then
    ok "_worklog tree clean"
  else
    warn "_worklog tree has uncommitted changes"
  fi
else
  warn "_worklog not cloned (run bin/install-worklog.sh)"
fi

echo "doctor: hooks"
settings="$HOME/.claude/settings.json"
# Council item #4: smallest tool that works. jq -e returns non-zero when the
# filter result is false/null/missing; the filter asserts both events exist
# and at least one inner command contains "autosave".
if [[ ! -f "$settings" ]]; then
  warn "hooks not wired ($settings absent — run install-worklog.sh)"
elif ! jq empty "$settings" 2>/dev/null; then
  fail "settings.json malformed (not valid JSON)"
elif jq -e '
    [.hooks.PreCompact[]?.hooks[]?.command | strings] | any(. | contains("autosave"))
  ' "$settings" >/dev/null 2>&1 \
    && jq -e '
    [.hooks.SessionEnd[]?.hooks[]?.command | strings] | any(. | contains("autosave"))
  ' "$settings" >/dev/null 2>&1; then
  ok "Claude Code hooks wired (PreCompact + SessionEnd → autosave)"
else
  warn "hooks not wired (PreCompact + SessionEnd missing autosave commands in $settings)"
fi

echo "doctor: gh auth"
if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated"
else
  warn "gh not authenticated (gh auth login — needed for private repos)"
fi

echo
if [[ $FAIL -eq 0 ]]; then
  echo "doctor: $WARN warning(s), all critical checks passed"
  exit 0
else
  echo "doctor: $FAIL failure(s), $WARN warning(s) — fix failures and re-run"
  exit 1
fi
