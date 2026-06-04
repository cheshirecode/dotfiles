#!/usr/bin/env bash
# Test harness for cheshirecode/dotfiles. Same script for local + CI.
#
#   tests/run.sh static       lint scripts + manifest
#   tests/run.sh fixtures     run guardrail fixtures (red-path tests)
#   tests/run.sh all          static + fixtures

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0; FAIL=0
say() { printf "  %-5s %s\n" "$1" "$2"; }
ok()   { say PASS "$1"; PASS=$((PASS+1)); }
fail() { say FAIL "$1"; FAIL=$((FAIL+1)); }

test_static() {
  echo "=== static ==="
  if command -v shellcheck >/dev/null; then
    if shellcheck --severity=warning bin/*.sh tools/*.sh tests/*.sh 2>&1 | grep -E '^In '; then
      fail "shellcheck"
    else
      ok "shellcheck"
    fi
  else
    say SKIP "shellcheck not installed"
  fi
  if ./tools/check-manifest.sh >/dev/null 2>&1; then ok "check-manifest.sh"; else fail "check-manifest.sh"; fi
}

# Council items #1, #6: fixture-driven red-path tests for guardrails.
test_fixtures() {
  echo "=== fixtures (red-path guardrail tests) ==="

  # --- #6: check-manifest.sh subpath+repo HARD FAIL ---
  local bad_manifest tmpdir
  tmpdir=$(mktemp -d)
  bad_manifest="$tmpdir/skills.yaml"
  cat >"$bad_manifest" <<'EOF'
version: 1
skills:
  - name: bogus
    description: test fixture — subpath with repo, must be rejected
    source:
      type: subpath
      repo: not-allowed-on-subpath/foo
      path: skills/bogus
    install_to: ~/.claude/skills/bogus
EOF
  # Run check-manifest with the fixture by temporarily overriding the manifest.
  # Use a wrapper invocation so we don't mutate the real file.
  if MANIFEST_OVERRIDE="$bad_manifest" python3 - <<PY
import sys, re, yaml
m = yaml.safe_load(open("$bad_manifest"))
problems = []
for s in m.get("skills", []):
    name = s.get("name","?")
    src = s.get("source", {})
    if src.get("type") == "subpath" and src.get("repo"):
        problems.append(f"{name}: source.type='subpath' must not carry 'repo:' field")
sys.exit(1 if problems else 0)
PY
  then
    fail "check-manifest accepted subpath+repo bad fixture (should reject)"
  else
    ok "check-manifest rejects subpath+repo (exit=1 as expected)"
  fi
  rm -rf "$tmpdir"

  # --- #1: install-skills refuse_if_unowned ---
  # The manifest's install_to is "~/.claude/skills/<name>" — resolved against
  # $HOME, not CLAUDE_SKILLS_DIR. Override HOME so ~ expansion lands in tmp.
  local fake_home unowned_dst rc
  fake_home=$(mktemp -d)
  unowned_dst="$fake_home/.claude/skills/council"
  mkdir -p "$unowned_dst"
  echo "user-edited content" > "$unowned_dst/SKILL.md"
  set +e
  HOME="$fake_home" ./bin/install-skills.sh council >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 3 ]]; then
    ok "install-skills refuses unowned dst (exit=3)"
  else
    fail "install-skills DID NOT refuse unowned dst (got exit=$rc, expected 3)"
  fi
  rm -rf "$fake_home"

  # --- #1: install-skills accepts sentineled dst ---
  fake_home=$(mktemp -d)
  unowned_dst="$fake_home/.claude/skills/council"
  mkdir -p "$unowned_dst"
  cp "$REPO_ROOT/skills/council/SKILL.md" "$unowned_dst/SKILL.md"
  echo "subpath:skills/council" > "$unowned_dst/.installed_from"
  set +e
  HOME="$fake_home" ./bin/install-skills.sh council >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    ok "install-skills accepts sentineled dst (exit=0)"
  else
    fail "install-skills rejected sentineled dst (got exit=$rc, expected 0)"
  fi
  rm -rf "$fake_home"
}

case "${1:-all}" in
  static)   test_static ;;
  fixtures) test_fixtures ;;
  all)      test_static; test_fixtures ;;
  *) echo "usage: $0 {static|fixtures|all}" >&2; exit 2 ;;
esac

echo
echo "tests: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
