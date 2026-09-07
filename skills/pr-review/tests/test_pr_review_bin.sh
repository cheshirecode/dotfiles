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
# The repo-wide lane now covers these scripts. Keep this focused check so a
# failure reports against pr-review directly too.
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

echo "=== 11. explicit tokens reach forge API calls ==="
FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'GH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "auth status") exit 0 ;;
  "api user")
    [[ -z "${REQUIRE_GH_TOKEN:-}" || "${GH_TOKEN:-}" == "$REQUIRE_GH_TOKEN" ]] || exit 42
    # NO_CURRENT_USER prints nothing. A CURRENT_GH_USER="" cannot express this:
    # the ${:-alice} default treats empty and unset alike.
    [[ -z "${NO_CURRENT_USER:-}" ]] || exit 0
    printf '%s\n' "${CURRENT_GH_USER:-alice}"
    ;;
  "pr view")
    [[ -z "${REQUIRE_GH_TOKEN:-}" || "${GH_TOKEN:-}" == "$REQUIRE_GH_TOKEN" ]] || exit 42
    # KNOWN_PR: any other number 404s the way real gh does (exit 1, stderr).
    [[ -z "${KNOWN_PR:-}" || "${3:-}" == "$KNOWN_PR" ]] || {
      echo "could not resolve to a PullRequest with the number of ${3:-}" >&2
      exit 1
    }
    # EMPTY_PR: exit 0 having printed nothing -- the silent-success shape.
    [[ -z "${EMPTY_PR:-}" ]] || exit 0
    # NULL_AUTHOR: valid JSON, author null. This is the shape that reaches the
    # author guard; an empty payload is caught earlier, so it cannot.
    [[ -z "${NULL_AUTHOR:-}" ]] || {
      printf '{"number":7,"title":"fixture","isDraft":false,"state":"OPEN","author":null}\n'
      exit 0
    }
    printf '{"number":7,"title":"fixture","isDraft":false,"state":"OPEN","author":{"login":"%s"},"commits":[{"authors":[{"login":"%s"}]}]}\n' \
      "${PR_AUTHOR:-alice}" "${COMMIT_AUTHOR:-alice}"
    ;;
  *) exit 42 ;;
esac
GH
chmod +x "$FAKE_BIN/gh"

out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" REQUIRE_GH_TOKEN=sentinel \
  "$BIN/pr-query.sh" view 7 --repo "$TMP/gh" --token sentinel 2>/dev/null)"
st=$?
[[ "$st" -eq 0 && "$out" == *'"number":7'* ]] \
  && pass "pr-query forwards --token to gh" \
  || fail "pr-query did not forward --token to gh (rc=$st)"

out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" REQUIRE_GH_TOKEN=sentinel \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" --token sentinel 2>/dev/null)"
st=$?
[[ "$st" -eq 0 && "$out" == "self" ]] \
  && pass "owner-check forwards --token to gh" \
  || fail "owner-check did not forward --token to gh (rc=$st, out=$out)"

echo "=== 12. only the PR author owns the PR ==="
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" \
  CURRENT_GH_USER=alice PR_AUTHOR=bob COMMIT_AUTHOR=alice \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 1 && "$out" == "other" ]] \
  && pass "a matching commit author does not claim another user's PR" \
  || fail "commit author incorrectly claimed another user's PR (rc=$st, out=$out)"

echo "=== 13. merge-base uses the remote default branch ==="
git init -q --bare --initial-branch=main "$TMP/base-remote.git"
git clone -q "$TMP/base-remote.git" "$TMP/base-seed" 2>/dev/null
git -C "$TMP/base-seed" -c user.name=fixture -c user.email=fixture@example.com \
  commit -q --allow-empty -m A
git -C "$TMP/base-seed" push -q origin main
git clone -q "$TMP/base-remote.git" "$TMP/base-review"
git -C "$TMP/base-seed" -c user.name=fixture -c user.email=fixture@example.com \
  commit -q --allow-empty -m B
git -C "$TMP/base-seed" push -q origin main
git -C "$TMP/base-review" fetch -q origin main
git -C "$TMP/base-review" switch -q -c feature origin/main
git -C "$TMP/base-review" -c user.name=fixture -c user.email=fixture@example.com \
  commit -q --allow-empty -m C
out="$("$BIN/pr-query.sh" merge-base --repo "$TMP/base-review" 2>/dev/null)"
expected="$(git -C "$TMP/base-review" merge-base origin/main HEAD)"
[[ "$out" == "$expected" ]] \
  && pass "merge-base follows origin/main instead of stale local main" \
  || fail "merge-base used stale local main (got=$out, want=$expected)"

echo "=== 14. missing option values exit instead of hanging ==="
expect_usage_exit() { # <label> <command...>
  local label="$1" pid st i
  shift
  "$@" >/dev/null 2>&1 & pid=$!
  i=0
  while kill -0 "$pid" 2>/dev/null && [[ "$i" -lt 10 ]]; do
    sleep 0.05
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    fail "$label hung on a missing option value"
    return
  fi
  wait "$pid"; st=$?
  [[ "$st" -eq 2 ]] && pass "$label exits 2 on a missing option value" \
                       || fail "$label exits $st on a missing option value"
}
for option in --repo --token; do
  expect_usage_exit "detect-forge $option" "$BIN/detect-forge.sh" "$option"
done
for option in --repo --token --author --limit; do
  expect_usage_exit "pr-query $option" "$BIN/pr-query.sh" view 7 "$option"
done
for option in --repo --token; do
  expect_usage_exit "owner-check $option" "$BIN/owner-check.sh" 7 "$option"
done

echo "=== 15. a PR that does not exist is an error, not an owner ==="
# 1d. Two ways the forge can fail to hand back a PR, and both must exit 2 with
# an empty stdout. A consumer branches on "self"/"other", so any stdout here
# would be read as an ownership verdict.
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" KNOWN_PR=7 \
  "$BIN/owner-check.sh" 999999 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 2 ]] && pass "a missing PR exits 2" || fail "missing PR must exit 2, got $st"
[[ -z "$out" ]] && pass "a missing PR prints nothing to stdout" \
                || fail "missing PR must print nothing, got '$out'"

err="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" KNOWN_PR=7 \
  "$BIN/owner-check.sh" 999999 --repo "$TMP/gh" 2>&1 >/dev/null)"
[[ "$err" == *999999* ]] && pass "the error names the PR number" \
                         || fail "the error must name the PR number, got '$err'"

# The silent half: gh exits 0 and prints nothing. Without the empty-data guard
# the author would parse to "" and compare equal to an empty current user,
# reporting "self" on a PR that was never read.
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" EMPTY_PR=1 \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 2 && -z "$out" ]] \
  && pass "an empty PR payload exits 2 instead of claiming ownership" \
  || fail "empty payload must exit 2 with no stdout, got rc=$st out='$out'"

# A well-formed payload with a null author is the case an empty-payload check
# cannot reach: the JSON is valid, so only the author guard is left. Left
# unguarded, the blank author compares equal to nothing and the script would
# have to pick a verdict -- and "self" is the unsafe pick, granting the lighter
# self-check mode on a PR whose owner was never established.
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" NULL_AUTHOR=1 \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 2 && -z "$out" ]] \
  && pass "a null author exits 2 rather than guessing an owner" \
  || fail "null author must exit 2 with no stdout, got rc=$st out='$out'"

# An unresolvable current user must stop, not compare. This is the guard that
# makes the `-n "$AUTHOR"` term in the comparison unreachable: without it, a
# blank author and a blank current user would compare equal and report "self".
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" NO_CURRENT_USER=1 \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 2 && -z "$out" ]] \
  && pass "an unresolvable current user exits 2" \
  || fail "unresolvable current user must exit 2 with no stdout, got rc=$st out='$out'"

echo "=== 16. the current user's own PR reports self ==="
# 1e. Section 11 already exercises this path, but only as the tail of a token
# assertion. Pinned here on its own so a self-detection regression cannot hide
# behind a token failure.
out="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FAKE_BIN:$PATH" \
  CURRENT_GH_USER=alice PR_AUTHOR=alice COMMIT_AUTHOR=bob \
  "$BIN/owner-check.sh" 7 --repo "$TMP/gh" 2>/dev/null)"
st=$?
[[ "$st" -eq 0 && "$out" == "self" ]] \
  && pass "the PR author is reported as self" \
  || fail "own PR must be self with exit 0, got rc=$st out='$out'"

if [[ "$FAIL" -ne 0 ]]; then
  echo "pr-review bin: FAILURES above" >&2
  exit 1
fi
echo "pr-review bin: all cases pass"
