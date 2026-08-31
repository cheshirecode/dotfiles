# Handover prompt

Copy-paste this at the start of a new harness session whenever you want the
agent to re-verify the installed loop-engineering skill and improve it on
demand. It is host-agnostic — resolve `<skill-dir>` before sending.

```
Use loop-engineering orchestrator mode. Goal: audit the installed loop-engineering skill for correctness, multi-host compatibility, and clarity; fix any issues found, then finish complete with verification evidence.

You are running in parallel with other sessions that may also be auditing this skill. Be tolerant of conflicts: if you must edit a file another session is changing, keep improvements that enhance clarity or safety, and resolve minor formatting disagreements locally.

First, resolve <skill-dir> (roots checked in order; gate on non-empty output,
never on find's exit code — a shimmed find can exit 1 after printing a match):
  for r in ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills; do found_file="$(find -L "$r" -name loop_state.py -print -quit 2>/dev/null)"; test -n "$found_file" && break; done; test -n "$found_file" && dirname "$(dirname "$found_file")"
If the command prints nothing, ask me which harness you are in and I will tell you.

Then follow these steps IN ORDER, one bash call per step:

Step 1 — sanity checks (pass fast; capture each suite's own exit code — tail
alone would report the pipeline's status, the exact trap examples.md §6 documents):
  python3 <skill-dir>/scripts/loop_state.py validate --state /dev/null 2>&1 || true
  T=$(mktemp); printf '[]' > "$T"; python3 <skill-dir>/scripts/loop_state.py validate --state "$T" 2>&1 | grep -c 'must be a JSON object'; rm -f "$T"
  out=$(bash <skill-dir>/tests/test_crew_radar.sh 2>&1); echo "radar rc=$?"; printf '%s\n' "$out" | tail -1
  out=$(bash <skill-dir>/tests/test_crew_reap.sh 2>&1); echo "reap rc=$?"; printf '%s\n' "$out" | tail -1
  wc -l <skill-dir>/SKILL.md

Step 2 — run the Python test suite (capture, don't pipe: ${PIPESTATUS[0]} is
bash-only and silently empty under zsh, the Claude Code harness shell):
  out=$(cd <skill-dir> && python3 -m unittest tests.test_loop_state tests.test_skill_budget tests.test_install_audit 2>&1); echo "unittest rc=$?"; printf '%s\n' "$out" | grep -E '^Ran [0-9]+ tests|^OK|^FAILED'

Step 3 — check for regressions (each grep feeds a Step 4 clause):
  echo "--- non-existent skill references ---"
  grep -nE '[$][a-z-]*(thinking|helpers|sequential)' <skill-dir>/references/orchestrator.md <skill-dir>/SKILL.md 2>/dev/null || echo "(none)"
  echo "--- route matrix missing serialize writes ---"
  grep 'delegates run concurrently.*serialize writes' <skill-dir>/SKILL.md || echo "(not found)"
  echo "--- frontmatter description length ---"
  sed -n '3p' <skill-dir>/SKILL.md | wc -c

Step 4 — decide:
  - If ANY rc above is nonzero OR the non-dict guard line printed 0 OR the
    stale-skill grep printed matches OR the route-matrix grep printed
    "(not found)" OR frontmatter > 450 chars OR unittest ran fewer than 51
    tests OR radar reported fewer than 27 passed OR reap fewer than 39 passed:
    BEGIN IMPROVEMENT LOOP (use bounded cycles via loop_state.py advance/finish).
  - If everything is clean AND you have nothing new to add:
    Report "CLEAN: <test-count> tests, <skill-line>-line SKILL.md, 0 issues."
    Then stop. Do NOT invent problems.

Step 5 — if improving:
  Use a bounded loop (budget 20 turns, unit=turns). For each cycle:
    a. Identify ONE specific issue.
    b. Edit the smallest affected file.
    c. Re-run relevant tests (`python3 -m unittest ...`).
    d. Advance via `loop_state.py advance --quiet`.
  Handle concurrent-edit conflicts gracefully: prefer merging your improvement
  over reverting, but never force-write over a conflicting file without checking.
  Finish with `finish --status complete --verification "<test-result>"`.

Return exactly one final line:
  <status>: <evidence>
where <status> is CLEAN or IMPROVED, and <evidence> names each changed file
and its test result. Keep all detail in the state artifact, not your output.
```

## Parallel-session notes

- **Race detection**: if two sessions edit the same file simultaneously, the
  second will either get a git merge conflict (if committed) or overwrite the
  first's changes (if only in-memory). Your job is to ensure BOTH improvements
  survive the merge when they land.
- **State independence**: each session has its own `loop_state.json` in /tmp.
  Conflicts only appear at the git commit layer, not in loop state tracking.
- **No stalemate protocol**: if a file is locked or conflicted from parallel
  edits, resolve by taking the union of both improvements where possible,
  or the more conservative safety-enforcing version where they disagree.
- **Verification is shared**: once one session finishes and pushes, the others
  should pull and re-verify rather than duplicating work. But it's acceptable
  for multiple sessions to independently confirm a clean state.

## Why this works

- **Auto-resolves** `<skill-dir>` without asking — handles Claude/Codex/Cursor/Opencode.
- **Sanity-first**: exits fast on broken installs without burning context.
- **Deterministic gates**: specific grep targets prevent false positives from agents
  that "see" problems that aren't there.
- **Budget-bounded**: caps at 20 improvement turns so a healthy skill doesn't waste tokens on drive-by refactors.
- **Pass-fast on clean**: explicit instruction to STOP when everything checks out avoids noise on stable installations.
- **Parallel-safe**: aware that other agents may run this same prompt simultaneously; resolved conflicts preserve all valid improvements.
