#!/usr/bin/env bash
# Post-install assertion. Returns non-zero if anything's broken.
#
# Checks (in order):
#   1. Runtime deps on PATH (python3, gh, git, rg, jq, direnv)
#   2. Python ≥ 3.10 (worklog lint helpers depend on 3.10+ syntax)
#   3. PyYAML importable (install-skills.sh uses it)
#   4. Each manifest skill present under Claude, shared-agent, and Cursor roots
#   5. _worklog repo present and on a clean HEAD
#   6. Hooks wired (.claude/settings.json mentions autosave)
#   7. gh auth (warn-only — works for unauth'd public-repo flows)

set -uo pipefail  # no -e: we collect all failures, exit non-zero at the end

# Four states, not three. OK / FAIL / WARN collapsed two different answers
# into WARN: "this is not installed" and "I could not tell". A missing reader
# then read the same as a passing one, which is the defect class CLAUDE.md
# records under "A diagnostic must separate absent from ok".
#
#   OK       checked, healthy
#   FAIL     checked, broken — gates the exit code
#   ABSENT   the thing genuinely is not here; actionable, and not a failure
#            on its own because some of it is optional
#   UNKNOWN  the probe itself could not answer. Never counts as healthy.
#   WARN     present and working, but worth saying
FAIL=0
WARN=0
ABSENT=0
UNKNOWN=0
say()     { printf "  %-7s %s\n" "$1" "$2"; }
ok()      { say "OK"      "$1"; }
fail()    { say "FAIL"    "$1"; FAIL=$((FAIL+1)); }
warn()    { say "WARN"    "$1"; WARN=$((WARN+1)); }
absent()  { say "ABSENT"  "$1"; ABSENT=$((ABSENT+1)); }
unknown() { say "UNKNOWN" "$1"; UNKNOWN=$((UNKNOWN+1)); }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/manifest/skills.yaml"
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
CURSOR_SKILLS_DIR="${CURSOR_SKILLS_DIR:-$HOME/.cursor/skills}"
SKILL_ROOTS=("$CLAUDE_SKILLS_DIR" "$AGENT_SKILLS_DIR" "$CURSOR_SKILLS_DIR")
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
print('\n'.join(f\"{s['name']}\\t{str(bool(s.get('optional'))).lower()}\" for s in yaml.safe_load(open('$MANIFEST'))['skills']))
" 2>"$skill_list_err")
  if [[ -z "$skill_list" ]] && [[ -s "$skill_list_err" ]]; then
    fail "manifest parse error: $(cat "$skill_list_err")"
  fi
  rm -f "$skill_list_err"
  while IFS=$'\t' read -r name optional; do
    [[ -z "$name" ]] && continue
    for skill_root in "${SKILL_ROOTS[@]}"; do
      skill_md="$skill_root/$name/SKILL.md"
      if [[ -f "$skill_md" ]]; then
        ok "$name → $skill_md"
      elif [[ "$optional" == true ]]; then
        ok "$name optional and not installed at $skill_root"
      else
        warn "$name SKILL.md missing at $skill_root (run bin/install-skills.sh)"
      fi
    done
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
# Wrapped in `direnv exec`, deliberately. A tool shell loads no .envrc, so a
# bare `gh auth status` reports the machine-wide token whatever directory it
# names — see CLAUDE.md, "A tool shell has no direnv". Unwrapped, this check
# could report a healthy login while the tree it is standing in resolves a
# different account entirely.
if ! command -v gh >/dev/null; then
  absent "gh not installed (needed for private repos)"
elif ! command -v direnv >/dev/null; then
  unknown "gh auth unverifiable: direnv missing, so a bare check would report the machine-wide token rather than this tree's"
else
  gh_out="$(direnv exec "$REPO_ROOT" gh auth status 2>&1)"
  gh_rc=$?
  if [[ $gh_rc -eq 0 ]]; then
    ok "gh authenticated as $(printf '%s' "$gh_out" | sed -n 's/.*account \([^ ]*\).*/\1/p' | head -1) in $REPO_ROOT"
  elif printf '%s' "$gh_out" | grep -q 'is blocked'; then
    # direnv refused to load the .envrc, so the token this tree would use was
    # never resolved. That is an unanswered probe, not a rejected credential —
    # reporting it as FAIL is the same absent-vs-broken collapse this check
    # exists to remove. Seen first on a fresh git worktree, whose .envrc has
    # never been approved.
    unknown "gh auth unverifiable: .envrc not approved for $REPO_ROOT (run: direnv allow $REPO_ROOT)"
  elif printf '%s' "$gh_out" | grep -qi 'not logged\|no accounts'; then
    absent "gh not authenticated (gh auth login — needed for private repos)"
  else
    fail "gh auth rejected in $REPO_ROOT: $(printf '%s' "$gh_out" | grep -i 'failed\|error' | head -1)"
  fi
fi

# The identity gate, per vault. A hook that is not installed protects nothing,
# and WORKLOG_IDENTITY_DOMAIN unset makes pre-commit-identity report and skip.
# Both halves must hold, and each can fail in a different way — which is why
# this is read as four states rather than a boolean.
echo "doctor: vault identity gate"
# Overridable so the states below can be exercised against scratch vaults;
# a check whose failure paths cannot be reached is not a check.
IFS=':' read -r -a VAULTS <<< "${WORKLOG_VAULTS:-$HOME/Documents/oss/_worklog:$PROJECTS_DIR/_worklog}"
for vault in "${VAULTS[@]}"; do
  short="${vault/#$HOME/~}"
  if [[ ! -d "$vault/.git" ]]; then
    absent "$short not cloned here"
    continue
  fi
  hooks="$(git -C "$vault" config core.hooksPath 2>/dev/null)"
  case "$hooks" in
    "")  hooks="$vault/.git/hooks" ;;
    /*)  ;;
    *)   hooks="$vault/$hooks" ;;
  esac
  if [[ ! -e "$hooks/pre-commit-identity" ]]; then
    fail "$short identity hook not installed (bin/install-hooks.sh --write)"
    continue
  fi
  if ! command -v direnv >/dev/null; then
    unknown "$short gate unverifiable: direnv missing, so WORKLOG_IDENTITY_DOMAIN cannot be read the way a commit reads it"
    continue
  fi
  # Read it from the vault, not from here: an export in a parent scope proves
  # nothing about what the consumer sees.
  domain="$(cd "$vault" && direnv exec . sh -c 'printf %s "${WORKLOG_IDENTITY_DOMAIN:-}"' 2>/dev/null)"
  if [[ -n "$domain" ]]; then
    ok "$short identity gate armed"
  else
    fail "$short identity gate DISARMED: hook installed but WORKLOG_IDENTITY_DOMAIN unset, so it reports and skips"
  fi
done

echo
summary="$FAIL failure(s), $WARN warning(s), $ABSENT absent, $UNKNOWN unknown"
if [[ $FAIL -eq 0 && $UNKNOWN -eq 0 ]]; then
  echo "doctor: $summary — all critical checks passed"
  exit 0
elif [[ $FAIL -eq 0 ]]; then
  # An unanswered probe is not a pass. Exit 2 keeps it distinct from a real
  # failure so a caller can tell "broken" from "could not tell".
  echo "doctor: $summary — nothing failed, but some checks could not answer"
  exit 2
else
  echo "doctor: $summary — fix failures and re-run"
  exit 1
fi
