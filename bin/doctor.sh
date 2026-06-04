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
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    skill_md="$SKILLS_DIR/$name/SKILL.md"
    if [[ -f "$skill_md" ]]; then
      ok "$name → $skill_md"
    else
      warn "$name SKILL.md missing (run bin/install-skills.sh)"
    fi
  done < <(python3 -c "import yaml,sys; print('\n'.join(s['name'] for s in yaml.safe_load(open('$MANIFEST'))['skills']))" 2>/dev/null)
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
# Council guardrail #9: JSON-schema check, not substring grep. A comment
# containing "autosave" used to pass the old `grep -q autosave` test.
if [[ ! -f "$settings" ]]; then
  warn "hooks not wired ($settings absent — run install-worklog.sh)"
else
  hook_check=$(python3 - "$settings" <<'PY' 2>/dev/null
import json, sys, os
try:
    cfg = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"PARSE_ERROR:{e}")
    sys.exit(0)
hooks = cfg.get("hooks") or {}
problems = []
for event in ("PreCompact", "SessionEnd"):
    matchers = hooks.get(event) or []
    cmds = []
    for m in matchers:
        for h in (m.get("hooks") or []):
            cmd = h.get("command") or ""
            if "autosave" in cmd:
                cmds.append(cmd)
    if not cmds:
        problems.append(f"{event}: no autosave hook")
        continue
    # Resolve $PROJECTS_DIR / $WORKLOG_DIR if present; otherwise check literal path.
    found_executable = False
    for cmd in cmds:
        # cheap path extraction — first whitespace-separated token containing autosave
        for tok in cmd.split():
            if "autosave" in tok:
                # expand env vars commonly used
                p = os.path.expandvars(os.path.expanduser(tok))
                if os.path.isfile(p) and os.access(p, os.X_OK):
                    found_executable = True
                break
    if not found_executable:
        problems.append(f"{event}: autosave hook points at non-executable path")
print("OK" if not problems else "; ".join(problems))
PY
)
  case "$hook_check" in
    OK) ok "Claude Code hooks wired (PreCompact + SessionEnd → autosave)" ;;
    PARSE_ERROR:*) fail "settings.json is malformed: ${hook_check#PARSE_ERROR:}" ;;
    *) warn "hooks check: $hook_check" ;;
  esac
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
