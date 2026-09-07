#!/usr/bin/env bash
# Contracts for pr-review's three forge scripts.
#
# The scripts landed with no fixture at all, and each documented a contract its
# code did not keep. Every case below was proved red against that first version:
#
#   detect-forge.sh   set CLI="gh" inside classify_remote, which runs in a
#                     command substitution. The assignment died with the
#                     subshell, so field 3 was always empty while the header
#                     documented "gh"|"glab". Its only consumer hardcoded the
#                     CLI instead of reading the field, so nothing failed loudly.
#   detect-forge.sh   ${GLAB_TOKEN:-GITLAB_TOKEN:-} defaults to the LITERAL
#                     string "GITLAB_TOKEN:-", which is never empty. A GitLab
#                     clone on a machine with no glab installed therefore
#                     reported authenticated success, exit 0 -- the confident
#                     wrong value, not a loud failure.
#   pr-query.sh       the flag loop consumed every argument, so the positional
#                     PR number hit the `*)` arm: `view 1` exited 2 with
#                     "unknown argument: 1". Four of its five operations were
#                     unreachable.
#   owner-check.sh    error paths used echo "...\n..." (bash echo does not
#                     expand \n), printing a literal backslash-n to the user.
#
# Exit: 0 all cases pass, 1 otherwise.

set -uo pipefail

BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Two throwaway clones. No network: every assertion below reads the remote URL
# and the local CLI inventory only.
mk_repo() { # <dir> <remote-url>
  mkdir -p "$1" && git -C "$1" init -q 2>/dev/null
  git -C "$1" remote add origin "$2"
}
mk_repo "$TMP/gh" "git@github.com:acme/widget.git"
mk_repo "$TMP/gl" "https://gitlab.com/acme/gadget.git"

echo "=== 1. detect-forge names the CLI it resolved ==="
out="$("$BIN/detect-forge.sh" --repo "$TMP/gh" --token dummy 2>/dev/null)"
IFS=$'\t' read -r forge slug cli _reason <<<"$out"
[[ "$forge" == "github" ]] && pass "github remote classified" || fail "github remote classified, got '$forge'"
[[ "$slug" == "acme/widget" ]] && pass "slug parsed from ssh remote" || fail "slug parsed, got '$slug'"
# RED before the fix: CLI was assigned inside a command substitution.
[[ "$cli" == "gh" ]] && pass "cli field is 'gh'" || fail "cli field must be 'gh', got '$cli'"

out="$("$BIN/detect-forge.sh" --repo "$TMP/gl" --token dummy 2>/dev/null)"
IFS=$'\t' read -r forge slug cli _reason <<<"$out"
[[ "$forge" == "gitlab" ]] && pass "gitlab remote classified" || fail "gitlab remote classified, got '$forge'"
[[ "$cli" == "glab" ]] && pass "cli field is 'glab'" || fail "cli field must be 'glab', got '$cli'"

echo "=== 2. a missing CLI is reported, never defaulted into success ==="
# The literal-string default made this exit 0 with an empty reason. Skipped only
# when glab really is installed, where the probe has a genuine answer to give.
if command -v glab >/dev/null 2>&1; then
  pass "skipped: glab is installed on this machine"
else
  out="$(env -u GLAB_TOKEN -u GITLAB_TOKEN "$BIN/detect-forge.sh" --repo "$TMP/gl" 2>/dev/null)"
  st=$?
  IFS=$'\t' read -r _f _s _c reason <<<"$out"
  [[ "$reason" == "glab-not-installed" ]] \
    && pass "absent glab reported as glab-not-installed" \
    || fail "absent glab must report glab-not-installed, got reason='$reason'"
  [[ "$st" -eq 3 ]] && pass "absent CLI exits 3" || fail "absent CLI must exit 3, got $st"
fi

echo "=== 3. detect-forge separates a bad target from a bad forge ==="
"$BIN/detect-forge.sh" --repo "$TMP/not-a-repo" >/dev/null 2>&1; st=$?
[[ "$st" -eq 2 ]] && pass "non-repo exits 2 (usage)" || fail "non-repo must exit 2, got $st"

echo "=== 4. every script is executable ==="
# pr-query.sh shipped mode 644. SKILL.md invokes it as "$SCRIPT_DIR/pr-query.sh",
# which then fails with exit 126 -- and 126 is not any of the three exit codes
# its header documents, so a caller reading the contract cannot classify it.
for script in owner-check.sh detect-forge.sh pr-query.sh; do
  [[ -x "$BIN/$script" ]] && pass "$script has the execute bit" \
                          || fail "$script is not executable (mode $(stat -f '%Lp' "$BIN/$script" 2>/dev/null))"
done

echo "=== 5. pr-query accepts the positional PR number ==="
# RED before the fix: the flag loop consumed every argument, so the number hit
# the `*)` arm and `view 7` exited 2 with "unknown argument: 7".
# Run through `bash` on purpose: section 4 owns the mode bits, and invoking the
# path directly would score a chmod failure (exit 126) as a passing contract.
for op in view diff ci-status; do
  err="$(bash "$BIN/pr-query.sh" "$op" 7 --repo "$TMP/gh" --token dummy 2>&1 >/dev/null)"
  st=$?
  if [[ "$err" == *"unknown argument: 7"* ]]; then
    fail "pr-query $op rejects its own PR number: $err"
  else
    pass "pr-query $op accepts a PR number"
  fi
  # A network-less run may fail, but never as a usage error.
  if [[ "$st" -eq 2 ]]; then
    fail "pr-query $op exited 2 (usage) on valid args: $err"
  else
    pass "pr-query $op does not exit 2 on valid args"
  fi
done

echo "=== 6. pr-query still rejects genuinely unknown flags ==="
bash "$BIN/pr-query.sh" view 7 --nonsense x >/dev/null 2>&1; st=$?
[[ "$st" -eq 2 ]] && pass "unknown flag exits 2" || fail "unknown flag must exit 2, got $st"

echo "=== 7. merge-base resolves without a PR number ==="
out="$(bash "$BIN/pr-query.sh" merge-base --repo "$REPO_ROOT" 2>/dev/null)"
[[ "$out" =~ ^[0-9a-f]{40}$ ]] && pass "merge-base prints a SHA" || fail "merge-base must print a SHA, got '$out'"

echo "=== 8. error text reaches the user as text, not as backslash-n ==="
# RED before the fix: four echo calls in owner-check.sh embedded a literal \n.
for script in owner-check.sh detect-forge.sh pr-query.sh; do
  if grep -n 'echo "[^"]*\\n' "$BIN/$script" >/dev/null 2>&1; then
    fail "$script uses echo with a literal \\n (use printf)"
  else
    pass "$script emits no literal \\n"
  fi
done

echo "=== 9. no script reaches across skill directories ==="
# pr-query.sh called ../worklog/bin/forge-prs.sh. Skills install into separate
# directories, so that path resolves only when both happen to be siblings.
for script in owner-check.sh detect-forge.sh pr-query.sh; do
  if grep -n '\.\./[a-z-]*/bin/' "$BIN/$script" >/dev/null 2>&1; then
    fail "$script depends on a sibling skill by relative path"
  else
    pass "$script has no cross-skill relative path"
  fi
done

echo "=== 10. the scripts pass shellcheck ==="
# tests/run.sh shellchecks bin/ tools/ tests/ at the repo root only; skills/*/bin
# is outside that sweep, so these three were never linted.
if command -v shellcheck >/dev/null 2>&1; then
  sc="$(shellcheck --severity=warning "$BIN"/*.sh 2>&1 | grep -E '^In ')"
  if [[ -n "$sc" ]]; then
    fail "shellcheck findings:"
    printf '%s\n' "$sc" >&2
  else
    pass "shellcheck clean at --severity=warning"
  fi
else
  pass "skipped: shellcheck not installed"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "pr-review bin: FAILURES above" >&2
  exit 1
fi
echo "pr-review bin: all cases pass"
