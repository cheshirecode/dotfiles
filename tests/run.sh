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

# Council #31: worklog skill bin/ — static lint + fixture-vault smoke. Catches
# the relocation-class regression where bin/foo.sh sibling-script calls drift
# back to data-repo-relative paths after Phase-2 deleted in-repo bin/.
test_worklog_skill() {
  echo "=== worklog skill (shellcheck + ruff + fixture-vault smoke) ==="
  local skill="$REPO_ROOT/skills/worklog"
  local sb="$skill/bin"
  [[ -d "$sb" ]] || { fail "skills/worklog/bin/ missing"; return; }

  # 1. shellcheck on all .sh under skill bin/ (excluding git-hooks/ — same severity gate).
  if command -v shellcheck >/dev/null; then
    if shellcheck --severity=warning "$sb"/*.sh "$sb"/git-hooks/* 2>&1 | grep -E '^In ' >/dev/null; then
      fail "shellcheck skills/worklog/bin/"
    else
      ok "shellcheck skills/worklog/bin/ (incl. git-hooks)"
    fi
  else
    say SKIP "shellcheck not installed"
  fi

  # 2. python syntax + ruff (skip ruff if absent).
  if python3 -m compileall -q "$sb" 2>&1 | grep -q .; then
    fail "python compile skills/worklog/bin/"
  else
    ok "python compile skills/worklog/bin/"
  fi
  if command -v ruff >/dev/null; then
    if ruff check "$sb" >/dev/null 2>&1; then
      ok "ruff skills/worklog/bin/"
    else
      ruff check "$sb" 2>&1 | head -10 >&2
      fail "ruff skills/worklog/bin/"
    fi
  else
    say SKIP "ruff not installed"
  fi

  # 3. Fixture-vault smoke. Bootstrap a throwaway data repo using the skill's
  # init-new-data-repo.sh; then exercise the core mode surface against it.
  local vault rc
  vault=$(mktemp -d)/test-vault
  set +e
  bash "$sb/init-new-data-repo.sh" "$vault" test-ldap >/dev/null 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 && -f "$vault/AGENTS.md" && -d "$vault/people/test-ldap/active" ]]; then
    ok "init-new-data-repo bootstraps clean (vault @ $vault)"
  else
    fail "init-new-data-repo failed (rc=$rc)"
    rm -rf "$(dirname "$vault")"
    return
  fi

  # Idempotent re-run: zero diffs in working tree.
  set +e
  bash "$sb/init-new-data-repo.sh" "$vault" test-ldap >/dev/null 2>&1
  if [[ -z "$(git -C "$vault" status --porcelain)" ]]; then
    ok "init-new-data-repo idempotent (no diff on re-run)"
  else
    fail "init-new-data-repo NOT idempotent — re-run dirtied the tree"
  fi
  set -e

  # Run preamble + status + lint against the throwaway vault.
  local out
  out=$(WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap bash "$sb/preamble.sh" --minimal 2>&1)
  if echo "$out" | grep -q 'LDAP=test-ldap'; then
    ok "preamble.sh --minimal resolves vault LDAP"
  else
    fail "preamble.sh --minimal (got: $(echo "$out" | head -1))"
  fi

  out=$(WORKLOG_REPO="$vault" WORKLOG_LDAP=test-ldap bash "$sb/status.sh" --since=today 2>&1)
  if echo "$out" | grep -q 'test-ldap'; then
    ok "status.sh resolves vault LDAP"
  else
    fail "status.sh"
  fi

  out=$(WORKLOG_REPO="$vault" bash "$sb/lint.sh" 2>&1)
  if echo "$out" | grep -qE '0 errors'; then
    ok "lint.sh runs clean against empty vault"
  else
    fail "lint.sh against empty vault (got: $(echo "$out" | head -2 | tr '\n' ' '))"
  fi

  # Empty-bin guard fires.
  echo '#!/bin/bash' > "$vault/bin/forbidden.sh"
  set +e
  ( cd "$vault" \
      && git -c core.hooksPath="$sb/git-hooks" add -f bin/forbidden.sh \
      && git -c core.hooksPath="$sb/git-hooks" commit -m "smoke" >/dev/null 2>&1 )
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    ok "pre-commit empty-bin guard rejects bin/foo.sh"
  else
    fail "pre-commit guard FAILED to reject (commit went through)"
  fi

  # Hard-fail when WORKLOG_REPO unset + cwd outside any clone.
  out=$( cd /tmp && bash "$sb/kernels-roster.sh" 2>&1 || true )
  if echo "$out" | grep -q 'cannot locate'; then
    ok "scripts hard-fail outside a worklog clone"
  else
    fail "expected hard-fail outside clone, got: $(echo "$out" | head -1)"
  fi

  rm -rf "$(dirname "$vault")"
}

case "${1:-all}" in
  static)         test_static ;;
  fixtures)       test_fixtures ;;
  worklog-skill)  test_worklog_skill ;;
  all)            test_static; test_fixtures; test_worklog_skill ;;
  *) echo "usage: $0 {static|fixtures|worklog-skill|all}" >&2; exit 2 ;;
esac

echo
echo "tests: $PASS pass, $FAIL fail"
[[ $FAIL -eq 0 ]]
