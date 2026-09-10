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
  evidence, not the orchestrator's recollection. This governs the *completion
  signal* only — see "Relaying a delegate's claim" below before any conclusion
  of a delegate's travels further.
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

An orchestrator must verify effect boundaries before dispatching mutations. Every
sub-agent that writes must run the protocol's effect preflight (§2,
[references/protocol.md](references/protocol.md)) to confirm target, authority,
and read-only proof before writing. If any answer is unknown, finish
`needs_human` with the missing authority named. Record `model-routing: skipped
— no delegate surface` when routing was unavailable.

Then either:
- **Delegate** to a sub-agent via `task` tool — pass the compact context pack
  directly; do not pass the parent transcript. Instruct the sub-agent to
  commit its evidence, uncertainty, and proposed next action to the worklog
  task file and call `archive.sh`, then capture the SHA via `git -C "$WORKLOG_REPO" log -1 --format=%H` and emit exactly one status line:
  `archived <child-slug> <sha>` (or `blocked|needs_human|failed
  <child-slug> <reason>`). The orchestrator discards any prose beyond that
  line. Never use `HEAD` from the code worktree or `gh pr view --json headRefOid`;
  the SHA must come from `git -C "$WORKLOG_REPO" log -1 --format=%H`. Reject a
  return whose `log -1 --format=%s` does not start with `<child-slug>:`.
- **Execute in-band** — do the work yourself if it is small and well-scoped.
  Write evidence to the task file, checkpoint, and archive.

Fable 5.1 delegates in coding loops may issue one tool call per turn when the
next independent calls are implied rather than requested; end each delegate
prompt with the official batching nudge: "First privately list what you need
next; then request every item that doesn't depend on another's result in this
one response."

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

### Relaying a delegate's claim makes it yours

Adopted from Fleet Deck's orchestrator doctrine, which paid for it. A delegate's
return carries two different kinds of thing, and the token rule above covers
only the first:

- **Facts about the run** — branch pushed, file moved, task archived. Cheap to
  check against the board, the worklog commit, or `git`. Take them as given.
- **Claims about the domain** — "X is the rollout gate", "that field is
  unused", "the migration is safe". These are conclusions, not evidence, and
  the delegate's context that produced them is gone.

Verify a domain claim before it shapes another child's context pack, reaches a
PR description, a ticket, or the human — or pass it on explicitly as that
delegate's *unverified* claim. Measured cost of skipping this: a wrong "the
`publish.py` weights are the rollout gate" travelled into an MR, a ticket and a
human update before anyone read the code; the real gate was upstream, and the
retraction cost more than the check would have.

This does not reopen the no-re-read rule. Archiving a child still needs nothing
but its one status line. The gate applies at the moment a conclusion leaves the
child's own task file — which is exactly when the cheap path stops being cheap.

Cycle decision record: Before any action that changes the hypothesis, write a
compact three-part record (`hypothesis: <claim>`, `falsifier: <observable result
that would reject it>`, `replay: <exact check after fix>`). See §Cycle decision
record in [references/protocol.md](references/protocol.md) for the full contract.
This prevents false positives when fixes are applied incrementally.

That's it. The diff, the findings, the verification — all in the worklog
commit, not in the orchestrator's loop state.

What that actually costs, measured over 100 cycles (2026-09-09): the state
file reaches **23KB** — one evidence line plus one history entry per cycle,
~230 bytes each — but the orchestrator never re-reads it. Only the driver's
single printed line enters context, at ~120 bytes, so 100 cycles cost about
**12KB of transcript**. Quote the transcript figure, not the file size; an
earlier "~1KB even after 100+ cycles" here understated the file by ~23x and
invited the state file to be treated as a free scratchpad. It is an index, and
the per-cycle line is the budget.

PR-watch / in-flight HEAD moves: if a host-native fingerprint watcher reports a
move while a review delegate is still running, record one evidence line
(`github: repo#N head <old>→<new> — <slug> in-flight`) and **do not interrupt**
the worker unless the user asked. A stale-SHA archive is valid cycle evidence.
Without that watcher (including Codex), recheck the head after the delegate
returns (`wait_agent` on Codex) and before the serialized write/archive step;
do not imply continuous observation.
After it lands, compare `gh pr view --json headRefOid` to the SHA in the archive
summary; mismatch → claim a pre-declared `review-pr-N-r2` child (or start a new
wave project), or add one with `project.sh add-child <project> <child>`. Do not
hand-write an orphan `review-pr-N` with a project back-reference but no
parent `tasks:` entry. `project verify` now rejects both undeclared children and
missing declared child files; `add-child` is the supported way to make work
reachable. These cases are pinned by the Worklog project fixtures.
`project verify` must exit 0 before the rereview claim.

### Plan before you pay for an expensive child

`interrogate.md` gates the *run*; this gates a *child*. When a child is costly
or its approach is genuinely unclear, spend one cycle producing a plan and
review that, rather than reviewing a branch. A bad split caught at plan time
costs one cheap delegate; caught at review time it costs the implementation,
the review, and the re-cut.

Dispatch the child in plan mode, have it return the plan rather than execute
it, and decide: approve (dispatch a fresh delegate to build it), revise, or
drop. Record the decision in the child's task file so the next cycle sees a
reviewed plan and not a fresh question. Where the right design is genuinely
contested, racing two or three planners on the same child and picking one is
still cheap next to building the wrong thing once.

Keep this off the default path. Most children are well-scoped enough that a
plan phase is pure overhead — use it when the child is expensive, irreversible,
or the decomposition itself was uncertain (the same trigger that sends
decomposition to `$council`).

### 4. Terminal

Use `project.sh next <slug> --json`: schema `worklog-project-next/v1` reports
`eligible`, `empty`, `blocked`, `missing`, or `error`. Exit 0 accompanies an
eligible task; other statuses use exit 1. Bootstrap failures may have no JSON.
Validate both the result and exit code; never infer completion from exit 1 alone.
Claims remain the responsibility of `project.sh claim next`.

For completion, set `run_dir`, `program_slug`, `LOOP_RUN` (the driver path),
`EVIDENCE_GATE` (the evidence-gate script), and `completion_gate`. The gate must
already contain verified evidence for the project's goal outcomes; it is not a
substitute for the checkpoint, project verification, and successful archive push
below. This recipe's gate covers goal outcomes; the archive is separately checked
and recorded in the terminal evidence. If your gate also declares archive delivery,
record that criterion and recheck its digest after the successful archive instead.

```bash
set -e
queue_rc=0
"$WORKLOG_BIN/project.sh" next "$program_slug" --json > "$run_dir/project-next.json" || queue_rc=$?
python3 - "$run_dir/project-next.json" "$queue_rc" "$program_slug" <<'PY_QUEUE'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if not (sys.argv[2] == "1" and data.get("schema_version") == "worklog-project-next/v1"
        and data.get("project") == sys.argv[3] and data.get("status") == "empty"
        and data.get("task") is None):
    sys.exit("project is not complete: " + str(data.get("reason") or data.get("status")))
PY_QUEUE
python3 "$EVIDENCE_GATE" check --gate "$completion_gate" > "$run_dir/gate-check.json"
verification="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verification"])' "$run_dir/gate-check.json")"
"$WORKLOG_BIN/checkpoint.sh" "$program_slug" --next="Verify rollup and archive project"
"$WORKLOG_BIN/project.sh" verify "$program_slug" > "$run_dir/project-verify.log"
"$WORKLOG_BIN/archive.sh" "$program_slug" --reason=shipped --summary="Project goal verified; child tasks archived"
archive_sha="$(git -C "$WORKLOG_REPO" rev-parse HEAD)"
python3 "$LOOP_RUN" "$run_dir" --stop complete --verification "$verification" \
  --evidence "git: $archive_sha — project verified and parent archive pushed"
```

A failed checkpoint, verification, gate, or archive push stops this recipe before
loop completion. Keep the run recoverable and inspect the exact failed command;
an archive file or local commit alone does not prove its push succeeded. For
blocked or missing work, use the driver's resumable stop with a concrete replay
`--next-action`. Budget exhaustion is owned by the state machine; do not compute
or invent a second budget in this recipe.

Return to `SKILL.md` for bounded-cycle and effect rules.
