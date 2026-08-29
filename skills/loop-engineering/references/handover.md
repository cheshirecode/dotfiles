# Handover prompt

Copy-paste this at the start of a new harness session whenever you want the
agent to re-verify the installed loop-engineering skill and improve it on
demand. It is host-agnostic — resolve `<skill-dir>` before sending.

```
Use loop-engineering orchestrator mode. Goal: audit the installed loop-engineering skill for correctness, multi-host compatibility, and clarity; fix any issues found, then finish complete with verification evidence.

First, resolve <skill-dir>:
  find ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills -name loop_state.py -print -quit 2>/dev/null | head -1 | xargs dirname/../
If the command fails, ask me which harness you are in and I will tell you.

Then follow these steps IN ORDER, one bash call per step:

Step 1 — sanity checks (pass fast):
  python3 <skill-dir>/scripts/loop_state.py validate --state /dev/null 2>&1 || true
  python3 <skill-dir>/tests/test_crew_radar.sh 2>&1 | tail -1
  wc -l <skill-dir>/SKILL.md

Step 2 — run the Python test suite:
  cd <skill-dir> && python3 -m unittest tests.test_loop_state tests.test_skill_budget tests.test_install_audit -v 2>&1 | tail -8

Step 3 — check for regressions (grep every known issue surface):
  echo "--- non-existent skill references ---"
  grep -n '\$[a-z]*\(thinking\|helpers\|sequential' <skill-dir>/references/orchestrator.md <skill-dir>/SKILL.md 2>/dev/null || echo "(none)"
  echo "--- route matrix missing serialize writes ---"
  grep 'delegates run concurrently' <skill-dir>/SKILL.md || echo "(not found)"
  echo "--- examples.md leaked metadata ---"
  tail -10 <skill-dir>/references/examples.md
  echo "--- frontmatter description length ---"
  sed -n '3p' <skill-dir>/SKILL.md | wc -c
  echo "--- fallback SKILL_DIR includes /. ---"
  grep 'Fallback' -A1 <skill-dir>/SKILL.md
  echo "--- crew.md OpenCode column ---"
  grep -c 'OpenCode\|task tool' <skill-dir>/references/crew.md

Step 4 — decide:
  - If ANY test failed OR frontmatter > 450 chars OR route matrix lacks
    "serialize writes" OR examples.md still contains shot_count/format:
    BEGIN IMPROVEMENT LOOP (use bounded cycles via loop_state.py advance/finish).
  - If everything is clean AND the harness asks you to continue anyway:
    Report "CLEAN: <test-count> tests, <skill-line>-line SKILL.md, 0 issues."
    Then stop. Do NOT invent problems.

Step 5 — if improving:
  Use a bounded loop (budget 20 turns, unit=turns). For each cycle:
    a. Identify ONE specific issue.
    b. Edit the smallest affected file.
    c. Re-run relevant tests (`python3 -m unittest ...`).
    d. Advance via loop_state.py --quiet.
  Finish with `finish --status complete --verification "<test-result>"`.

Return exactly one final line:
  <status>: <evidence>
where <status> is CLEAN or IMPROVED, and <evidence> names each changed file
and its test result. Keep all detail in the state artifact, not your output.
```

## Why this works

- **Auto-resolves** `<skill-dir>` without asking — handles Claude/Codex/Cursor/Opencode.
- **Sanity-first**: exits fast on broken installs without burning context.
- **Deterministic gates**: specific grep targets prevent false positives from agents
  that "see" problems that aren't there.
- **Budget-bounded**: caps at 20 improvement turns so a healthy skill doesn't waste tokens on drive-by refactors.
- **Pass-fast on clean**: explicit instruction to STOP when everything checks out avoids noise on stable installations.
