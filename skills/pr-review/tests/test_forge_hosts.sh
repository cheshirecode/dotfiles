#!/usr/bin/env bash
# Cases 4a-4c from test_plan.md: which hosts count as a known forge.
#
# The defect this pins: the host arms were `github.*` and `gitlab.*`, so a
# self-hosted `github.mycompany.com` classified as forge=github, cli=gh,
# exit 0. The caller then runs `gh` against an Enterprise host that the
# user's gh credentials do not cover. That is the confident wrong value --
# forge=other yields an empty cli and a loud "unsupported forge" instead.
#
# The rule under test: the SaaS host itself, or a subdomain of it. That keeps
# GitHub's and GitLab's own alternate SSH hosts working while rejecting any
# vendor-named host in someone else's domain.
#
# Exit: 0 all cases pass, 1 otherwise.

set -uo pipefail

BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
FAIL=0
pass() { printf '  PASS   %s\n' "$1"; }
fail() { FAIL=1; printf '  FAIL   %s\n' "$1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# classify <remote-url> -> "forge<TAB>slug<TAB>cli"
#
# mktemp, not a counter: this runs inside a process substitution, so a
# `n=$((n + 1))` here would increment in a subshell and die with it, leaving
# every case pointed at the same repo. That is the same subshell-assignment
# defect that left detect-forge's own cli field empty.
classify() {
  local d
  d="$(mktemp -d "$TMP/r.XXXXXX")"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" remote add origin "$1"
  "$BIN/detect-forge.sh" --repo "$d" --token dummy 2>/dev/null
}

# Fields are read positionally with awk, not with `IFS=$'\t' read`. Tab is an
# IFS *whitespace* character, so consecutive tabs collapse into one delimiter
# and an empty cli field silently slides the reason into $3 -- the read form
# reports cli=unsupported-forge-host where the script printed cli="".
field() { printf '%s\n' "$2" | awk -F'\t' -v n="$1" '{print $n}'; }

expect() { # <label> <url> <forge> <cli>
  local label="$1" url="$2" want_forge="$3" want_cli="$4" out forge cli
  out="$(classify "$url")"
  forge="$(field 1 "$out")"
  cli="$(field 3 "$out")"
  if [[ "$forge" == "$want_forge" && "$cli" == "$want_cli" ]]; then
    pass "$label"
  else
    fail "$label: want forge=$want_forge cli=$want_cli, got forge=$forge cli=$cli"
  fi
}

echo "=== 4a-4b. the SaaS hosts, in both URL forms ==="
expect "github ssh form"        "git@github.com:acme/widget.git"        github gh
expect "github https form"      "https://github.com/acme/widget.git"    github gh
expect "gitlab https form"      "https://gitlab.com/acme/gadget.git"    gitlab glab
expect "gitlab ssh form"        "git@gitlab.com:acme/gadget.git"        gitlab glab

echo "=== 4b-b. the vendors' own alternate hosts stay known ==="
expect "github alt ssh host"    "git@ssh.github.com:acme/widget.git"    github gh
expect "gitlab alt ssh host"    "git@altssh.gitlab.com:acme/gadget.git" gitlab glab

echo "=== 4c. a vendor-named host in another domain is NOT that forge ==="
# RED before the fix: `github.*` matched this and handed back cli=gh.
expect "self-hosted github"     "https://github.mycompany.com/acme/widget.git" other ""
expect "self-hosted gitlab"     "https://gitlab.mycompany.com/acme/gadget.git" other ""
# The suffix must be the domain, not a substring: notgithub.com is not GitHub.
expect "vendor name as prefix"  "https://notgithub.com/acme/widget.git"        other ""
# And a host that merely ends in the vendor word is not the vendor either.
expect "vendor word as tld"     "https://example.github/acme/widget.git"       other ""

echo "=== 4c-b. an unknown forge reports no CLI to run ==="
# forge=other with a non-empty cli would send the caller to the wrong tool.
out="$(classify "https://git.example.org/acme/widget.git")"
forge="$(field 1 "$out")"; cli="$(field 3 "$out")"; reason="$(field 4 "$out")"
[[ "$forge" == "other" && -z "$cli" ]] \
  && pass "an unknown host yields other with an empty cli" \
  || fail "unknown host must be other with empty cli, got forge=$forge cli=$cli"
# The reason field is the loud half: it must say why, not sit empty.
[[ -n "$reason" ]] \
  && pass "the reason field explains the unknown host ($reason)" \
  || fail "an unknown host must carry a reason, got empty"

if [[ "$FAIL" -ne 0 ]]; then
  echo "pr-review forge hosts: FAILURES above" >&2
  exit 1
fi
echo "pr-review forge hosts: all cases pass"
