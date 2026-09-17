#!/usr/bin/env bash
# No worklog script may commit what it did not stage.
#
# The vault checkout is shared: several agent sessions and a human can hold it
# at once. A bare `git commit` writes whatever is in the index, so one script
# run sweeps up another session's staged files. CLAUDE.md states the rule —
# "Never a bare `git commit` in a checkout another session may use" — and the
# vault's own scripts were breaking it.
#
# This guard enumerates every call site and requires each to be either scoped
# with `--only ... -- <paths>` or listed below as ONE LITERAL file:line with a
# written reason. A glob or a whole-file carve-out would silently exempt every
# site added later, which is the failure this file exists to prevent.
#
# Enumeration deliberately avoids an extension glob: bin/git-hooks/* are
# extensionless, and *.sh would skip them without saying so.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/skills/worklog/bin"

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

if [ ! -d "$BIN" ]; then
  # Absent is not ok: with no scripts this asserts nothing.
  echo "test_commit_pathspec NOT RUN — nothing was asserted; $BIN is missing." >&2
  exit 2
fi

# An exemption is a marker comment in the source, immediately above the call:
#
#   # commit-pathspec-exempt: <why this site may commit the whole index>
#
# Keyed on the marker, not on file:line. A line-numbered list was the first
# design and it broke the moment an unrelated edit shifted the file — the
# guard then reported two healthy sites as violations and silently stopped
# covering the two it had been pinned to. The reason also belongs next to the
# code it excuses, where the next person editing that line will read it.
MARKER='# commit-pathspec-exempt:'

scanned=0; scoped=0; exempted=0
unscoped=""

while IFS= read -r f; do
  rel="${f#"$BIN"/}"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    line="${hit%%:*}"
    scanned=$((scanned+1))
    site="$rel:$line"
    # A scoped commit names its paths with `--` on the same logical command.
    # Read a few lines forward: these calls wrap with trailing backslashes.
    window="$(sed -n "${line},$((line+6))p" "$f")"
    # Look back a few lines for the marker; the call may be preceded by a
    # short comment of its own.
    back="$(sed -n "$(( line > 4 ? line-4 : 1 )),$((line-1))p" "$f")"
    # tail, not head: take the NEAREST marker above the call. With head, a
    # site three lines below another site's marker inherited that site's
    # reason, so the wrong justification was printed for the wrong line.
    reason="$(printf '%s' "$back" | grep -F "$MARKER" | tail -1 | sed "s/.*$MARKER//" | sed 's/^ *//')"
    if printf '%s' "$window" | grep -q -- '--only' && printf '%s' "$window" | grep -qE -- '-- +"'; then
      scoped=$((scoped+1))
    elif [ -n "$reason" ]; then
      exempted=$((exempted+1))
      printf '  note  exempt %s — %s\n' "$site" "$reason"
    else
      unscoped="$unscoped$site "
    fi
  done < <(grep -nE '^[[:space:]]*git[[:space:]]+commit' "$f" 2>/dev/null | cut -d: -f1)
done < <(find "$BIN" -type f -not -path '*__pycache__*' | sort)

if [ "$scanned" -eq 0 ]; then
  echo "test_commit_pathspec NOT RUN — no commit call sites found, which means the enumeration is broken, not that the code is clean." >&2
  exit 2
fi

if [ -z "$unscoped" ]; then
  ok "every commit call site is pathspec-scoped or a named exemption ($scanned sites: $scoped scoped, $exempted exempt)"
else
  bad "commit sites that take the whole index and are not named exemptions: $unscoped"
fi

# The exemption list must not rot into a blanket. If it ever covers most of
# the sites, the guard has stopped guarding.
if [ "$exempted" -le "$scoped" ]; then
  ok "exemptions ($exempted) do not outnumber scoped sites ($scoped)"
else
  bad "more sites are exempt ($exempted) than scoped ($scoped) — the carve-out has become the rule"
fi

printf 'tests: %d pass, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
