# Orchestrator mode — multi-task program

Use when a high-level goal decomposes into 3+ independent tasks managed across
sub-agents. The agent acts as project manager: decompose, dispatch, verify,
track.

Keep detailed evidence in Worklog and record one typed index line per cycle:
`git: <worklog-sha> — <slug>: archived`. The parent verifies worker evidence and
serializes shared checkpoint/archive operations under [crew.md](crew.md).
Do not turn a worker's completion claim into verified progress without checking it.

Use delegation when the authorized host capability and task justify it; in-band
execution remains available. Read crew guidance before dispatching workers. Keep
parent history compact (`claim → verify → archive → advance`) and invoke optional
skills only when their triggers apply.

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
call records `git: <worklog-sha> — <slug>: archived`. No diff, no findings, no analysis — that
lives in the worklog task file.

```bash
# Pull next eligible task from queue
"$WORKLOG_BIN/project.sh" next <program-slug>

# Claim (advisory mutex — releases after stale_after if session dies)
"$WORKLOG_BIN/project.sh" claim <child-slug>

# Get compact context for dispatch
"$WORKLOG_BIN/context.sh" <child-slug> --for=compact
```

Use [crew.md](crew.md) to resolve the available dispatch capability and its
ownership boundary. A tool need not be named `task`. If dispatch is unavailable,
execute the child in-band when authorized, or stop with the missing capability
and replay action. Record `model-routing: skipped — no delegate surface` when
routing was not used.

Before dispatching mutations, run the protocol's effect preflight to confirm
target, authority, and read-only proof. Unknown authority stops the affected
mutation with `needs_human`; name the missing authority.

Pass the compact context pack directly. The worker returns the crew contract;
the parent verifies it and serializes shared Worklog writes. Code-worktree
isolation never implies separate Worklog ownership. For in-band work, the same
verification and persistence steps apply.

After the child's acceptance checks pass, the parent checkpoints and calls
`archive.sh` to release the claim and push evidence. Verify the archive commit
and successful push: its SHA comes from
`git -C "$WORKLOG_REPO" log -1 --format=%H`, and its subject must start with
`<child-slug>:`. A missing active file alone is insufficient. Record the archive
once; repeated worker messages do not consume another cycle.

```bash
# Record cycle — one typed line, no detailed findings
python3 <skill-dir>/scripts/loop_run.py <run-dir> \
  --evidence "git: <worklog-sha> — <slug>: archived" \
  --next-action "Claim next project task"
```

### Relaying a delegate's claim makes it yours

A delegate's return contains observations and conclusions. Verify both before
relaying them:

- **Facts about the run** — branch pushed, file moved, task archived. Cheap to
  check against the board, the worklog commit, or `git`. Recheck the named evidence.
- **Claims about the domain** — "X is the rollout gate", "that field is
  unused", "the migration is safe". These are conclusions, not evidence, and
  the delegate's context that produced them is gone.

Verify a domain claim before it shapes another child's context pack, reaches a
PR description, a ticket, or the human — or pass it on explicitly as that
delegate's *unverified* claim.

A compact index is sufficient only after the parent verifies the evidence and
archive delivery. Preserve detailed findings in the task for later review.

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
the worker unless the user asked. A stale-SHA archive is historical cycle evidence only; it cannot satisfy
current-head completion.
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
