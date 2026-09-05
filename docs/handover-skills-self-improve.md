# Handover: self-improve the dotfiles skills (any LLM harness, any model)

Copy-paste the block below into a fresh agent session on any harness
(Claude Code, Codex, Cursor, Opencode) and any model. It is self-contained.
The repo contains only skill content and its tests/checks; this shareable
prompt lives outside the repo on purpose. Update this file when the audit
rules change; the repo's tests are the ground truth when they disagree.

```
Goal: audit and self-improve the skills in the dotfiles repo. Fix what is
broken. Do not invent problems. Commit and push to main. Write in simple
technical English: short sentences, active voice, no idioms.

You may be running in parallel with other sessions. Pull before you start.
Rebase and re-verify if the remote moves. When you must edit a file another
session changed, merge both improvements; never force-push, never rewrite
history, never stash someone else's work away.

Step 0 — locate the repo and the skill directory:
  Repo: /Users/fredtran/Documents/oss/dotfiles (or clone
  github.com:cheshirecode/dotfiles and cd into it).
  git pull --ff-only first.
  Resolve <skill-dir> with the tested resolvers in
  skills/loop-engineering/SKILL.md, section "Resolve the skill directory".

Step 1 — install and verify BOTH dependencies. Do not skip either one.
   If an install fails, abort the run and report which dependency failed;
   do not proceed to audit gates without both tools verified.
   a. zvec-grep:
      command -v zg || npm install -g @zvec/zvec-grep   # needs Node 22+
      zg index            # from the repo root; .zvec-grep/ is gitignored here
      Verify all three lanes and record each result as one line:
        zg query --rg -F "RESUMABLE_STATUSES" skills/loop-engineering/scripts
          (expect file:line hits; NOTE: exits 0 even on no match — read the
           output, not $?)
        zg query --fts "crew radar overlap"          (expect ranked hits)
        zg query "where the loop driver decides continue versus stop"
          (expect skills/loop-engineering/SKILL.md as the top hit)
   b. caveman:
      command -v caveman || { npm install -g @caveman-ai/cli && caveman setup --install; }
      The engine is a separate binary; `caveman setup --install` fetches it.
      Verify against skills/loop-engineering/references/transport.md:
        seq 1 800 | sed 's/^/INFO heartbeat seq=/' > "$(mktemp -d)/rep.log"  # then shrink that file
        caveman tools shrink -- cat <that-file>      # expect a large token cut
        caveman tools shrink -- git log --oneline -20  # expect ratio 0, no fake win
        caveman retrieve <handle-from-first-shrink>  # expect all 800 lines back
      Do NOT run `caveman tools convert` on installed skills: they are
      symlinks into this repo, and convert on symlinks measures nothing.

Step 2 — use the tools during the audit. zg is the search tool for every
  shell search in this repo (fall back to rg only if zg cannot install).
  Use `caveman tools shrink` on any command output you expect to be large
  and repetitive; keep the recovery handle; skip it when the measured
  ratio is 0.

Step 3 — run the audit gates. There are NO test-count floors: suites grow,
  so never compare counts to a pinned number. Trust each suite's own
  pass/fail line and its own exit code. Capture the producer's exit code —
  `suite | tail` reports tail's status, not the suite's.
  a. cd <skill-dir> (loop-engineering) and run:
     python3 -m unittest discover -s tests -t tests -p 'test_*.py'
       (always discover; hand-listing modules under-counts the suite)
       gate: rc 0 and an OK line, no FAILED
     bash tests/test_crew_radar.sh    # gate: rc 0, "0 failed"
     bash tests/test_crew_reap.sh     # gate: rc 0, "0 failed"
  b. From the repo root:
     bash tests/run.sh all            # gate: rc 0, "0 fail"
     bash skills/worklog/tests/run.sh # gate: "0 failed" (1 skip is normal:
       log_compact/test_squash.sh needs a real vault; run it too with
       SOURCE=<path-to-a-real-worklog-data-repo> when one exists —
       on the primary machine both /Users/fredtran/Documents/oss/_worklog
       and /Users/fredtran/Documents/projects/_worklog work; the test
       clones and never touches the source repo)
   c. Regression greps on skills/loop-engineering (each 0/missing is a fail):
      no '^[\$][a-z-]*(thinking|helpers|sequential)' hits in SKILL.md or
        references/orchestrator.md      # anchor ^ so only leading $VAR patterns match
      'delegates run concurrently.*serialize writes' present in SKILL.md
      'references/interrogate.md' present in SKILL.md (the pre-init
        interrogation gate is routed)
      'one question at a time' and 'interrogation: skipped' present in
        references/interrogate.md
      SKILL.md is 260 lines or fewer; frontmatter description line is 450
        bytes or fewer (sed -n '3p' SKILL.md | wc -c); note: wc -c counts
        the trailing newline so compare line count <= 261, desc bytes <= 451

Step 4 — decide:
  If every gate passes and you have nothing real to add, report exactly:
    CLEAN [<harness>/<model>]: <one line of gate results>, 0 issues.
  Then stop. Do not invent problems to justify a commit.
  If any gate fails, or you find a concrete defect: improve.

Step 5 — improve with the skill's own driver, one call per cycle. The goal
  is fuzzy by construction, so dogfood the interrogation gate first
  (skills/loop-engineering/references/interrogate.md): self-review mode,
  record assumptions as evidence lines, declare
  --allowed-effect "git commit and push to main" and
  --approval-boundary "force-push, history rewrite, file deletion",
  and init only on a Ready verdict. Then (generate run-dir via mktemp -d):
  set RUN_DIR="$(mktemp -d)" && python3 <skill-dir>/scripts/loop_run.py "$RUN_DIR" --goal "<goal>" --budget 20
  Each cycle: fix ONE issue; prove any new test red before the fix
  (run it against the unfixed code and watch it fail — a guard that
  passes both ways certifies the bug); re-run the affected gate; then:
  python3 <skill-dir>/scripts/loop_run.py "$RUN_DIR" --evidence "command: <ref> — <result>"
   On apparent success, run the evidence-gate skill
   (scripts/evidence_gate.py): init --gate --goal --criterion "id=desc"...,
   then record every criterion per references/recording.md (not from memory):
     python3 scripts/evidence_gate.py record --gate <id> --criterion <id> --kind <kind> --ref <url-or-file> --result pass/fail
   then finish ONLY via:
   python3 <skill-dir>/scripts/loop_run.py "$RUN_DIR" --stop complete --verification "<evidence-gate verification value>"
  Never report blocked, budget_exhausted, or cancelled as complete.
  Keep run dirs and gate JSON in system temp (mktemp -d), never in the
  worktree.

Step 6 — ship:
  One concern per commit (guards, tests, and docs split), each commit green
  on its own. Conventional commit messages. git pull --rebase, push, then
  confirm `git ls-remote origin main` equals your local HEAD (a broken-pipe
  on the confirm is transient — retry the confirm, not the push).

Return exactly one final line:
  <CLEAN|IMPROVED> [<harness>/<model>]: <evidence — each changed file and
  its gate result>
The [<harness>/<model>] tag (e.g. [codex/gpt-5], [claude-code/fable-5],
[cursor/sonnet-5]) makes cross-runtime verifications distinguishable.
```

## Known state when this prompt was written (2026-09-04, head 83a5585)

- All gates green: discover OK (88), radar 31/31, reap 40/40, root harness
  133/0, worklog runner 48/0/1, squash gate passed on both real vaults.
- zg 0.2.1 and caveman CLI 1.3.1 / bin-v1.1.4 installed and verified on
  the primary machine.
- Recent shipped rounds, for context: fixed-/tmp-path race in five worklog
  fixtures (a463fcd + guard 81fc953); the guard's line-level $ exclusion
  was itself blind to `"$VAR" >/tmp/x` violations and is now token-level
  (0fdd70f); plan-interrogation gate adopted from alanw707/rpi-skills
  (4f73fc0, contract fb111c1); interrogation surfaces de-duped across
  karpathy-guidelines / worklog plan / interrogate.md (674b7db).
- Recurring trap: macOS ships bash 3.2 — no mapfile/readarray/declare -A
  in worklog bin/*.sh (guarded), and no bare `timeout` in test loops (the
  root harness resolves a portable one).
- Recurring trap: fixture outputs go to the test's own mktemp scratch dir,
  never to fixed /tmp paths (guarded, token-level).
- Recurring defect class ("adjacent pattern match"): a filter that excludes
  or matches whole lines when it means tokens. When you write a guard,
  inject a violation into a scratch copy and watch the guard fail before
  trusting it.
- SKILL.md is at exactly 260/260 lines; several exact strings and even
  line-wraps are pinned by tests/run.sh AND
  skills/loop-engineering/tests/test_loop_state.py — grep BOTH before
  trimming or reflowing anything in SKILL.md. Any root addition must first
  free lines (references/ files have no budget).
- The reference file set is pinned exactly in tests/run.sh ("host
  differences deferred"): adding a reference file requires updating that
  set in the same commit.
