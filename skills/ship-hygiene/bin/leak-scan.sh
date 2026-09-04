#!/usr/bin/env bash
# leak-scan.sh — find internal-process references in reviewer-facing text.
#
# Reads the text to scan on stdin. One place owns the pattern; SKILL.md step 7b
# used to carry two near-identical copies of it (one for the PR body, one for
# the diff), free to drift apart and duplicated in every fix.
#
# Usage:
#   gh pr view <n> --json title,body -q '.title + "\n" + .body' | leak-scan.sh --label body
#   gh pr diff <n> | grep -E '^\+' | leak-scan.sh --label diff
#   leak-scan.sh --print-pattern      # the regex, for ad hoc use
#
# Exit: 0 clean, 1 leaks found (a VERDICT, printed to stdout), 2 usage or a
# refusal to judge. Capture the status before parsing; do not pipe this into
# anything under `set -o pipefail` and read the pipeline's status as the
# verdict.
#
# It refuses to say "clean" over empty input. A failed `gh` call produces no
# bytes, and a scan of nothing is indistinguishable from a scan that found
# nothing -- which is the whole failure this script exists to avoid.

set -euo pipefail

PROG=${0##*/}

# One token per line, joined below. Keep it explicit: a generic "slash command"
# pattern also matches any URL path segment with a hyphen, and a false positive
# on a legitimate link trains people to ignore the scan.
TOKENS=(
  'worklog:'                          # the trailer form, not bare "worklog"
  'worklog [a-z0-9]+(-[a-z0-9]+){1,}'  # prose "worklog <slug>", no colon, no slash
  '\[POST-MERGE'
  'next_action'
  'people/[A-Za-z0-9._-]+/(active|archive)'   # task paths, either state
  'worklog/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+'   # the worklog_id frontmatter form
  'iteration [0-9]'
  'per the (audit|critique)'
  'scope chosen'
)

# Slash-command names. Every skill in this repo is a leakable command name, and
# tests/test_leak_scan.sh fails if a sibling skill directory is missing here --
# so adding a skill without extending this list is caught at the moment the
# skill is added, not the next time a leak ships.
SKILL_COMMANDS=(
  council evidence-gate example-led-instructions job-application
  karpathy-guidelines loop-engineering loop-helpers serena-rg-search
  ship-hygiene tightening-a-pr which-model worklog
)

build_pattern() {
  local joined commands
  joined="$(printf '%s|' "${TOKENS[@]}")"
  commands="$(printf '%s|' "${SKILL_COMMANDS[@]}")"
  printf '%s/(%s)' "$joined" "${commands%|}"
}

PATTERN="$(build_pattern)"
LABEL="input"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:?--label needs a value}"; shift 2 ;;
    --print-pattern) printf '%s\n' "$PATTERN"; exit 0 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
  esac
done

INPUT="$(cat)"
if [ -z "${INPUT//[[:space:]]/}" ]; then
  echo "$PROG: refusing to report '$LABEL' clean: nothing was read on stdin." >&2
  echo "  A failed gh call and a leak-free PR both produce no bytes here." >&2
  exit 2
fi

# grep exits 1 for "no matches", which is the clean verdict, not an error.
HITS="$(printf '%s\n' "$INPUT" | grep -inE "$PATTERN" || true)"
if [ -n "$HITS" ]; then
  printf '%s: %s — internal-ref leaks:\n' "$PROG" "$LABEL"
  printf '%s\n' "$HITS"
  exit 1
fi
printf '%s: %s — clean (%s lines scanned)\n' "$PROG" "$LABEL" \
  "$(printf '%s\n' "$INPUT" | wc -l | tr -d ' ')"
exit 0
