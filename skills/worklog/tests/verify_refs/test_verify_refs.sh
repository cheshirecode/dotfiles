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
repos: [example-repo]
---

## Context

Body cites !9999 and SPLUS-1 but the body is not scope.

## Next

- [ ] Chase !1234 before it rots
- [x] Already done, cites !5678 and must be ignored
- [ ] Also SPLUS-4321
EOF

task block-repos <<'EOF'
---
slug: block-repos
owner: tester
status: in-progress
kind: impl
repos:
  - monorepo
  - example-repo
---

## Context

Block-form repos:. The first entry is not example-repo.

## Next

- [ ] Chase !4321
EOF

task no-repos <<'EOF'
---
slug: no-repos
owner: tester
status: in-progress
kind: impl
---

## Context

No repos: field at all. The project is unknown, not example-repo.

## Next

- [ ] Chase !4321
EOF

task no-next <<'EOF'
---
slug: no-next
owner: tester
status: draft
kind: impl
repos: [example-repo]
---

## Context

No Next section at all.
EOF

run() {  # run <args...> -> sets OUT / RC, capturing before parsing (examples.md §6)
  OUT=$(cd "$TMP/wl" && WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
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

# stdout only: the setup notes go to stderr, and merging them in makes valid
# JSON unparseable (same reason as the error-path case below).
OUT=$(cd "$TMP/wl" && WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
      GITLAB_HOST=127.0.0.1:1 JIRA_HOST=127.0.0.1:1 \
      GITLAB_PAT=fake MCP_JIRA_EMAIL=t@t.t MCP_JIRA_API_TOKEN=fake \
      "$BIN/verify-refs.sh" --json with-refs 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.rows[0].ref' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  PASS  json is parseable\n'
else FAIL=$((FAIL+1)); printf '  FAIL  json unparseable: %s\n' "$OUT"; fi

# stdout only: die() writes a human line to stderr AND the JSON object to
# stdout, so merging the two makes valid JSON unparseable. Merging streams is
# the same class of mistake as piping a verdict into a parser.
OUT=$(cd "$TMP/wl" && WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
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

# A SUCCESSFUL lookup, which the unroutable-host fixtures above never reach —
# and so never caught that the MR half could not report a merged MR at all.
# GitLab returns the whole object on one line, and the old
#   sed -n 's/.*"state":"\([a-z]*\)".*/\1/p'
# is greedy, so it took the LAST "state" in the document (a nested author's
# "active") rather than the MR's own. Every resolvable MR came back live, which
# is exactly the "merged weeks ago and nothing notices" case this tool exists
# to catch. The fixture is the point: state:merged early, state:active trailing.
mkdir -p "$TMP/stub"
cat > "$TMP/stub/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */api/v4/user) printf '%s' '{"id":1}'; exit 0 ;;
    */rest/api/3/myself) printf '%s' '{"accountId":"a"}'; exit 0 ;;
    *merge_requests*) printf '%s' '{"iid":1682,"state":"merged","author":{"state":"active"},"merged_by":{"state":"active"}}'; exit 0 ;;
    *rest/api/3/issue*) printf '%s' '{"fields":{"status":{"statusCategory":{"key":"done"}}}}'; exit 0 ;;
  esac
done
exit 22
STUB
chmod +x "$TMP/stub/curl"

OUT=$(cd "$TMP/wl" && PATH="$TMP/stub:$PATH" WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
      GITLAB_HOST=gitlab.example JIRA_HOST=jira.example \
      GITLAB_PAT=fake MCP_JIRA_EMAIL=t@t.t MCP_JIRA_API_TOKEN=fake \
      "$BIN/verify-refs.sh" with-refs 2>&1)
ck "merged MR is reported stale, not live" 'stale.*!1234.*merged'
no "merged MR is not counted live"         '1 live'
ck "nested author state does not win"      '!1234'
no "working credentials print no setup note" 'note:'

# repos: block form. Only the inline shape was parsed, so every block-form
# task silently resolved to examplens/example-repo whatever its repos: actually said —
# measured 62 block-form tasks in one namespace, 15 naming another repo first.
# The stub answers only for monorepo, so a example-repo lookup falls through to
# unchecked and the assertion below fails, which is exactly the old behaviour.
# The two projects answer with DIFFERENT states for the SAME id. A stub where
# the wrong project merely 404s would only prove the loud failure; the one that
# matters is a low MR number that exists in both repos, resolves against the
# wrong one, and returns a confident wrong verdict with no signal. Here example-repo
# says opened, monorepo says merged: reading the wrong project yields "live".
cat > "$TMP/stub/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */api/v4/user) printf '%s' '{"id":1}'; exit 0 ;;
    */rest/api/3/myself) printf '%s' '{"accountId":"a"}'; exit 0 ;;
    *examplens%2Fmonorepo*merge_requests*) printf '%s' '{"iid":4321,"state":"merged","author":{"state":"active"}}'; exit 0 ;;
    *examplens%2Fexample-repo*merge_requests*)    printf '%s' '{"iid":4321,"state":"opened","author":{"state":"active"}}'; exit 0 ;;
    *merge_requests*) exit 22 ;;
  esac
done
exit 22
STUB
chmod +x "$TMP/stub/curl"

OUT=$(cd "$TMP/wl" && PATH="$TMP/stub:$PATH" WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
      GITLAB_HOST=gitlab.example JIRA_HOST=127.0.0.1:1 \
      GITLAB_PAT=fake \
      "$BIN/verify-refs.sh" block-repos 2>&1)
ck "block-form repos resolves to its own repo" 'stale.*!4321.*merged'
no "block-form repos does not default to example-repo" '(unchecked|live).*!4321'
no "wrong project cannot yield a confident live verdict" '1 live'

# A missing repos: must not be guessed. The stub answers for BOTH projects, so
# a default-to-example-repo would resolve and print a confident verdict; only refusing
# to guess yields unchecked.
OUT=$(cd "$TMP/wl" && PATH="$TMP/stub:$PATH" WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester WORKLOG_FORGE_NAMESPACE=examplens \
      GITLAB_HOST=gitlab.example JIRA_HOST=127.0.0.1:1 GITLAB_PAT=fake \
      "$BIN/verify-refs.sh" no-repos 2>&1)
ck "absent repos: reports unchecked, not a guess" 'unchecked.*!4321'
no "absent repos: does not silently resolve"      '(stale.*!4321|[1-9][0-9]* live)'

# Credential positive control. Every per-ref failure collapses to `unchecked`,
# so a missing MCP_JIRA_EMAIL, a revoked token and a dead network all printed
# the same row with nothing naming the cause (measured 2026-10-08: the email
# was absent from the shared secrets file). Each case below must NAME its cause,
# and a rejected credential must stop the per-ref calls rather than repeat them.
# The stub logs every URL so "no lookup was attempted" is asserted, not assumed.
cat > "$TMP/stub/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in https://*) echo "$a" >> "$STUB_LOG" ;; esac; done
for a in "$@"; do
  case "$a" in
    */api/v4/user)       [ "${STUB_GL:-ok}" = ok ]   && { printf '%s' '{"id":1}'; exit 0; }; exit 22 ;;
    */rest/api/3/myself) [ "${STUB_JIRA:-ok}" = ok ] && { printf '%s' '{"accountId":"a"}'; exit 0; }; exit 22 ;;
    *merge_requests*)    printf '%s' '{"iid":1234,"state":"opened"}'; exit 0 ;;
    *rest/api/3/issue*)  printf '%s' '{"fields":{"status":{"statusCategory":{"key":"indeterminate"}}}}'; exit 0 ;;
  esac
done
exit 22
STUB
chmod +x "$TMP/stub/curl"
creds() {  # creds <env assignments...> -> OUT, RC, LOG
  : > "$TMP/stub.log"
  OUT=$(cd "$TMP/wl" && env -u GITLAB_PAT -u GITLAB_TOKEN -u MCP_JIRA_EMAIL -u MCP_JIRA_API_TOKEN -u JIRA_HOST \
        PATH="$TMP/stub:$PATH" STUB_LOG="$TMP/stub.log" WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
        WORKLOG_FORGE_NAMESPACE=examplens GITLAB_HOST=gitlab.example "$@" \
        "$BIN/verify-refs.sh" with-refs 2>&1)
  RC=$?; LOG=$(cat "$TMP/stub.log")
}
JIRA_OK=(JIRA_HOST=jira.example MCP_JIRA_EMAIL=t@t.t MCP_JIRA_API_TOKEN=fake)

creds GITLAB_TOKEN=fake JIRA_HOST=jira.example MCP_JIRA_API_TOKEN=fake
ck "missing Jira email is named in a note"      'note: unset: MCP_JIRA_EMAIL; every Jira ref'
ck "missing Jira email is the row's reason"     'unchecked.*SPLUS-4321.*MCP_JIRA_EMAIL'
no "GITLAB_TOKEN alone is accepted (not only GITLAB_PAT)" 'unchecked.*!1234'

creds GITLAB_TOKEN=fake "${JIRA_OK[@]}" STUB_JIRA=bad
ck "rejected Jira credential is named"          'note: Jira credential check against jira.example: rejected'
if printf '%s' "$LOG" | grep -q 'rest/api/3/issue'; then FAIL=$((FAIL+1)); printf '  FAIL  looked up issues after Jira rejected the credential\n'
else PASS=$((PASS+1)); printf '  PASS  no issue lookups after Jira rejected the credential\n'; fi

creds "${JIRA_OK[@]}"
ck "missing GitLab token is named"              'note: GITLAB_TOKEN \(or GITLAB_PAT\) unset; every MR ref'
ck "missing GitLab token is the row's reason"   'unchecked.*!1234.*GITLAB_TOKEN'

creds GITLAB_TOKEN=fake "${JIRA_OK[@]}" STUB_GL=bad
ck "rejected GitLab token is named"             'note: GitLab token check against gitlab.example: rejected'
if printf '%s' "$LOG" | grep -q 'merge_requests'; then FAIL=$((FAIL+1)); printf '  FAIL  looked up MRs after GitLab rejected the token\n'
else PASS=$((PASS+1)); printf '  PASS  no MR lookups after GitLab rejected the token\n'; fi
[ "$RC" = 0 ] && { PASS=$((PASS+1)); printf '  PASS  a rejected credential still degrades (exit 0)\n'; } \
              || { FAIL=$((FAIL+1)); printf '  FAIL  a rejected credential changed the exit (%s)\n' "$RC"; }

creds GITLAB_TOKEN=fake "${JIRA_OK[@]}"
no "working credentials: no note"               'note:'
ck "working credentials: both refs resolved"    '0 stale, 2 live, 0 unchecked'
# Inert-lane guard: the probes must have run, or "no note" proves nothing.
printf '%s' "$LOG" | grep -q '/api/v4/user' && printf '%s' "$LOG" | grep -q '/rest/api/3/myself' \
  && { PASS=$((PASS+1)); printf '  PASS  both credential probes ran\n'; } \
  || { FAIL=$((FAIL+1)); printf '  FAIL  a credential probe never ran\n'; }

# WORKLOG_FORGE_NAMESPACE unset. The note was printed once per TASK, whether
# or not the task had an MR ref: a live run printed it 301 times for one
# project and buried the notes that mattered. And the MR rows gave the generic
# "unresolved repo, or the lookup failed" instead of the cause. Two tasks share
# example-repo here so a per-task note would print twice; no-next names
# example-repo with no refs at all, and a ref-less project must not be listed.
task with-refs-2 <<'EOF2'
---
slug: with-refs-2
owner: tester
status: in-progress
kind: impl
repos: [example-repo]
---

## Next

- [ ] Chase !2222
EOF2
task only-refless <<'EOF2'
---
slug: only-refless
owner: tester
status: in-progress
kind: impl
repos: [refless-repo]
---

## Next

- [ ] No ref here at all
EOF2
OUT=$(cd "$TMP/wl" && env -u WORKLOG_FORGE_NAMESPACE -u MCP_JIRA_EMAIL \
      PATH="$TMP/stub:$PATH" STUB_LOG="$TMP/stub.log" WORKLOG_REPO="$TMP/wl" WORKLOG_LDAP=tester \
      GITLAB_HOST=gitlab.example GITLAB_TOKEN=fake \
      "$BIN/verify-refs.sh" 2>&1)
n=$(printf '%s\n' "$OUT" | grep -c 'note: WORKLOG_FORGE_NAMESPACE')
[ "$n" = 1 ] && { PASS=$((PASS+1)); printf '  PASS  namespace note printed once per run\n'; } \
             || { FAIL=$((FAIL+1)); printf '  FAIL  namespace note printed %s times, want 1\n' "$n"; }
ck "the one note lists every skipped project"  'note: WORKLOG_FORGE_NAMESPACE unset; MR refs unchecked for example-repo, monorepo$'
no "a project without MR refs is not listed"   'refless-repo'
ck "namespace is the MR row's reason"          'unchecked +with-refs-2 +!2222 +WORKLOG_FORGE_NAMESPACE unset'
ck "missing repos: is its own reason"          'unchecked +no-repos +!4321 +task has no repos: field'
no "no MR row gives the generic reason"        'unresolved repo, or the lookup failed'
# Inert-lane guard: the rows must exist, or every "no" above passes vacuously.
ck "the namespace-less MR rows were emitted"   '0 stale, 0 live, [4-9] unchecked'

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
