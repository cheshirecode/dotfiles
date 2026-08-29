#!/usr/bin/env bash
# Contract fixtures for verify-refs.sh. Network-free: the lookups are stubbed by
# pointing GITLAB_HOST / JIRA_HOST at an unroutable address, so every ref lands
# on the degradation path. What is asserted here is scope and behaviour —
# which items are read, and that an unverifiable ref never blocks.
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
G() { git -c user.email=t@t.t -c user.name=t "$@"; }

G init -q --initial-branch=main "$TMP/wl"
mkdir -p "$TMP/wl/people/tester/active"
task() { cat > "$TMP/wl/people/tester/active/$1.md"; }

task with-refs <<'EOF'
---
slug: with-refs
owner: tester
status: in-progress
kind: impl
repos: [midas]
---

## Context

Body cites !9999 and SPLUS-1 but the body is not scope.

## Next

- [ ] Chase !1234 before it rots
- [x] Already done, cites !5678 and must be ignored
- [ ] Also SPLUS-4321
EOF

task no-next <<'EOF'
---
slug: no-next
owner: tester
status: draft
kind: impl
repos: [midas]
---

## Context

No Next section at all.
EOF

run() {  # run <args...> -> sets OUT / RC, capturing before parsing (examples.md §6)
  OUT=$(cd "$TMP/wl" && WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
        GITLAB_HOST=127.0.0.1:1 JIRA_HOST=127.0.0.1:1 \
        GITLAB_PAT=fake MCP_JIRA_EMAIL=t@t.t MCP_JIRA_API_TOKEN=fake \
        "$BIN/verify-refs.sh" "$@" 2>&1)
  RC=$?
}
ck() { local n=$1 p=$2; if printf '%s' "$OUT" | grep -Eq "$p"; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$n"
       else FAIL=$((FAIL+1)); printf '  FAIL  %s\n     wanted /%s/ in:\n%s\n' "$n" "$p" "$OUT"; fi; }
no() { local n=$1 p=$2; if printf '%s' "$OUT" | grep -Eq "$p"; then FAIL=$((FAIL+1)); printf '  FAIL  %s (found /%s/)\n' "$n" "$p"
       else PASS=$((PASS+1)); printf '  PASS  %s\n' "$n"; fi; }

run with-refs
ck "reads unchecked Next items"        '!1234'
ck "reads Jira refs too"               'SPLUS-4321'
no "ignores CHECKED Next items"        '!5678'
no "ignores refs outside ## Next"      '!9999'
[ "$RC" = 0 ] && { PASS=$((PASS+1)); printf '  PASS  unreachable host does not block (exit 0)\n'; } \
              || { FAIL=$((FAIL+1)); printf '  FAIL  unreachable host blocked (exit %s)\n' "$RC"; }
ck "unverifiable is reported, not passed" 'unchecked'

run no-next
ck "task without Next is a no-op"      '0 stale, 0 live, 0 unchecked'

run --json with-refs
if printf '%s' "$OUT" | jq -e '.rows[0].ref' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  PASS  json is parseable\n'
else FAIL=$((FAIL+1)); printf '  FAIL  json unparseable: %s\n' "$OUT"; fi

# stdout only: die() writes a human line to stderr AND the JSON object to
# stdout, so merging the two makes valid JSON unparseable. Merging streams is
# the same class of mistake as piping a verdict into a parser.
OUT=$(cd "$TMP/wl" && WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
      "$BIN/verify-refs.sh" --json /nope/nope 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.error' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  PASS  json on the error path\n'
else FAIL=$((FAIL+1)); printf '  FAIL  json error path: %s\n' "$OUT"; fi

# Exit 3 is a verdict. Lock the trap in both directions, as crew-radar and
# crew-reap do — see loop-engineering references/examples.md section 6.
printf 'stale|s|!1|p|merged\n' > "$TMP/probe"
(
  set -uo pipefail
  piped=$( { set -o pipefail; printf 'x\n' | grep x; } | tail -1 ) || piped="LOST"
  if [ "$piped" = "x" ]; then PASS=$((PASS+1)); printf '  PASS  harness sanity: pipeline of exit-0 survives\n'
  else FAIL=$((FAIL+1)); printf '  FAIL  harness sanity\n'; fi
)

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
