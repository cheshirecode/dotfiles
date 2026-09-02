# Orchestrator mode — multi-task program

Use when a high-level goal decomposes into 3+ independent tasks managed across
sub-agents. The agent acts as project manager: decompose, dispatch, verify,
track.

**Token efficiency is critical.** This mode is designed for sessions that run
days or weeks. Every token the orchestrator spends on per-task detail is a
token it cannot spend on dispatch. Follow these rules:

- **Evidence in loop_state is one line per cycle.** Just
  `<slug>: archived`. Per-task evidence lives in worklog task files
  (committed by the sub-agent), not in the orchestrator's memory.
- **Bulk generation offloading.** Never generate 3 or more repetitive structured files
  or template expansions in-band on frontier orchestrator tokens. Prepare a compact
  spec pack and delegate generation to a low-cost sub-agent (`mechanical` / utility model)
  to cut generation token costs by >85%.
- **Never re-read sub-agent output.** Check that the sub-agent completed
  (`archive.sh` pushed successfully) and move on. The worklog commit is the
  evidence, not the orchestrator's recollection.
- **Sub-agents own verification.** The sub-agent runs verification, writes
  results to the task file, checkpoints, and returns. The orchestrator only
  confirms the task is archived.
- **Compaction-friendly.** The orchestrator's history is a repeating pattern:
  `claim X → archive X → advance`. No diffs, no results, no analysis. This
  compresses cleanly.
- **Optional invocations are gated.** Invoke an optional skill only when its
  trigger is met; do not preload or invoke it as ceremony.

When tasks need concurrent delegates, read `references/crew.md` — same queue,
budget, and evidence rules, plus capability-gated isolation, serialized writes,
and the conflict radar.

### Natural language invocation

To invoke this mode, give the agent this prompt:

> Use loop-engineering. Goal: <goal>.

The agent resolves the rest from the documentation below. No flags, no syntax,
no setup instructions needed. The loop runs until the project queue is empty
(`project next` reports "all tasks ... are archived (nothing left)"; see §4 —
exit 1 alone is not proof), not until a fixed turn count.

### 1. Decompose & budget

Run task decomposition (`sequential-thinking` or manual analysis) only when the task graph is not already explicit or its dependencies are uncertain. If the user or Worklog already supplies a clear graph, construct the minimal tasks-json directly. Tasks are independent unless `depends_on` is set.

Budget is a **safety net**, not a planning constraint, only when the user has
not supplied a ceiling. If the user gives a budget, use that exact limit; never
silently replace it with 999. If the user gives both a minimum cycle count and
a ceiling, record the minimum in the goal and do not finish before that minimum
is met, even if the queue empties. Otherwise, use 999 as the default safety net
for a project whose real stopping condition is the queue emptying:
`project next` exits 1 when no eligible tasks remain; exit 1 also covers
blocked or missing children (see §4).

If decomposition uncertainty is high (ambiguous scope, unclear dependencies,
novel domain), run `$council` to debate the task breakdown before writing.

### Mid-run council escalation

An authorized orchestrator may invoke `$council` without a new user turn when a
running program crosses a material uncertainty trigger: independent task
returns disagree, a material counterexample appears, bounded retries fail, or
the task graph or scope becomes ambiguous. Pause only the affected mutation,
pass the council the original goal plus compact context and evidence, and do
not pass the full parent transcript.

Use the smallest escalation pack: `original goal`, `compact task context`,
`trigger`, `affected mutation`, `evidence`, `constraints`,
`one decision question`, and `replay check`. Accept only `verified` or
`UNVERIFIED` plus a decision; a verified result must pass the replay check
before the task resumes. A confirmed verdict carries
`decision: <one-sentence answer>` with the exact replay command.

Council is an advisory subloop, not success evidence. A verified council result
must be written to Worklog, followed by the discriminating replay check, and
then the normal claim → archive → advance sequence may resume. `UNVERIFIED`
results become `blocked` or `needs_human` with the exact replay check; never
archive or finish `complete` from a council verdict alone. Do not call
`advance` twice for one cycle; include escalation in that cycle unless it was
explicitly budgeted separately.

### 2. Create project

Derive the project slug from the program name, then auto-create child tasks:

```bash
echo '<tasks-json>' | "$WORKLOG_BIN/project.sh" new <slug> \
  --goal="<goal>" --objective="<objective>" --repos=<repo>
```

The tasks-json is the task decomposition output or directly constructed
graph mapped to `{slug, kind, depends_on}`.
`kind` must be one of the worklog set — `bug`, `bugfix`, `cleanup`, `debug`,
`design`, `impl`, `infra`, `investigation`, `ops`, `perf`, `plan`, `postmortem`,
`program`, `project`, `proposal`, `review`, `runbook`, `spike`, `tooling`. There
is no `fix` or `docs`; use `bugfix` and `infra` (`tooling` is accepted but legacy).
`plan-new` rejects an unknown
kind before writing anything, and lists the valid set in the error.
Each task is one cycle. Use the user-supplied budget when present; otherwise
set 999 as a safety net (the real limit is queue emptiness, not budget
exhaustion).

### 3. Each cycle

Token rule: **one line of evidence per cycle.** The orchestrator's advance
call is just `<slug>: archived`. No diff, no findings, no analysis — that
lives in the worklog task file.

```bash
# Pull next eligible task from queue
"$WORKLOG_BIN/project.sh" next <program-slug>

# Claim (advisory mutex — releases after stale_after if session dies)
"$WORKLOG_BIN/project.sh" claim <child-slug>

# Get compact context for dispatch
"$WORKLOG_BIN/context.sh" <child-slug> --for=compact
```

Before choosing a delegate, confirm that the current harness exposes the
`task` surface and that the approval boundary permits the dispatch. If either
check fails, do not fabricate a delegate result: execute the child in-band
when it is safe, or finish `needs_human` with the missing capability and replay
check. Record `model-routing: skipped — no delegate surface` when routing was
not used.

Then either:
- **Delegate** to a sub-agent via `task` tool — pass the compact context pack
  directly; do not pass the parent transcript. Instruct the sub-agent to
  commit its evidence, uncertainty, and proposed next action to the worklog
  task file and call `archive.sh`, then capture the SHA via `git -C "$WORKLOG_REPO" log -1 --format=%H`, and emit `archived <child-slug> <sha>` as the one-line return. After that, return exactly one status line:
  `archived <child-slug> <worklog-commit>` (or `blocked|needs_human|failed
  <child-slug> <reason>`); the orchestrator parses that line and discards any
  prose. The SHA is `git -C "$WORKLOG_REPO" log -1 --format=%H` after
  `archive.sh` succeeds — never `HEAD` from the code worktree and never
  `gh pr view --json headRefOid`. Reject a return whose `log -1 --format=%s`
  does not start with `<child-slug>:`.
- **Execute in-band** — do the work yourself if it is small and well-scoped.
  Write evidence to the task file, checkpoint, and archive.

Either way, the sub-agent or in-band execution must call `archive.sh` to
release the claim and push evidence to the worklog. The orchestrator then
only confirms the task is no longer in the active directory:

```bash
# Record cycle — one line, no details
python3 <skill-dir>/scripts/loop_state.py advance \
  --state <state-file> \
  --evidence "<slug>: archived" \
  --next-action "Claim next project task"
```

That's it. The diff, the findings, the verification — all in the worklog
commit, not in the orchestrator's loop state. This keeps the orchestrator's
context footprint at ~1KB even after 100+ cycles.

PR-watch / in-flight HEAD moves: if a host-native fingerprint watcher reports a
move while a review delegate is still running, record one evidence line
(`github: repo#N head <old>→<new> — <slug> in-flight`) and **do not interrupt**
the worker unless the user asked. A stale-SHA archive is valid cycle evidence.
Without that watcher (including Codex), recheck the head after the delegate
returns (`wait_agent` on Codex) and before the serialized write/archive step;
do not imply continuous observation.
After it lands, compare `gh pr view --json headRefOid` to the SHA in the archive
summary; mismatch → claim a pre-declared `review-pr-N-r2` child (or start a new
wave project). Do not spawn an orphan `review-pr-N` with `project:` set but
missing from the parent's `tasks:` block — `project.sh` has no add-child.
`project verify` must exit 0 before the rereview claim.

### 4. Terminal

When budget is consumed or the project queue is empty, capture the complete
`project next` result and verify the project before finishing. Exit 1 alone is
not proof of an empty queue: it also covers blocked or missing children. Treat
the queue as empty only when `project next` reports `all tasks ... are archived
(nothing left)` and `project verify <slug>` exits 0.

Before running the gate, rewrite the parent project file's `next_action` to
its rollup/completion step and checkpoint it: the default that `project.sh
new` writes ("Kick off — claim first eligible child ...") still requests
child work, so `project verify` warns and exits 1 on a legitimately finished
project (verified live 2026-08-31). Archive the parent after the gate passes.

```bash
program_slug="<program-slug>"
next_output="$("$WORKLOG_BIN/project.sh" next "$program_slug" 2>&1)" || true
if ! grep -Fq "all tasks for '$program_slug' are archived (nothing left)" <<<"$next_output"; then
  echo "$next_output" >&2
  exit 1
fi
if ! "$WORKLOG_BIN/project.sh" verify "$program_slug"; then
  echo "project verification failed" >&2
  exit 1
fi
python3 <skill-dir>/scripts/loop_state.py finish \
  --state <state-file> --status complete \
  --verification "project next reported all tasks archived; project verify exited 0" \
  --evidence "project queue empty: typed command output and project verification"
```

If `next_output` reports blocked or missing work, keep the state running or
finish `needs_human` with the exact replay check. If the queue still has tasks
but budget is exhausted, finish with `budget_exhausted` and the next eligible
task slug.

Return to `SKILL.md` for the bounded-cycle, evidence, and terminal-state rules.
