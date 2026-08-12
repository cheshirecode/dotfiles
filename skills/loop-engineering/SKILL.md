---
name: loop-engineering
description: Design and run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled engineering and research work. Use when an agent must iterate toward a verifiable condition, recover across context boundaries, coordinate subagents, or decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler. Skip trivial one-shot tasks. Orchestrator mode: use for multi-task programs with sub-agent dispatch.
---

# loop-engineering

Use deterministic state transitions around agent judgment. Repeated prompting is
not a loop design.

## Route

1. Skip this skill when one action plus one check is sufficient.
2. For interactive, resumable, or delegated loops, use the state script below.
3. For scheduled loops or installation drift, also read
   [references/hosts.md](references/hosts.md); require a real recurrence
   primitive for scheduling and use its audit command for duplicate copies.
4. For exact transition, effect, worklog, or handoff rules, read
   [references/protocol.md](references/protocol.md).

## Initialize through the script

Resolve `<skill-dir>` as this `SKILL.md` file's directory. Choose an explicit,
authorized state path; do not hand-edit its JSON.

```bash
python3 <skill-dir>/scripts/loop_state.py init \
  --state <state-file> \
  --goal "<observable success condition>" \
  --evidence "<current fact or artifact>" \
  --budget-unit "<turns|hypotheses|retries|minutes>" \
  --budget-limit <positive-integer> \
  --next-action "<smallest discriminating action>"
```

Add `--allowed-effect` and `--approval-boundary` whenever writes or external
effects are possible. If `python3` is unavailable, preserve the same five fields
manually and label the run as a non-deterministic fallback.

## Run one bounded cycle

1. Observe from tools or durable evidence.
2. Choose the smallest action that advances or falsifies the approach.
3. Check effect scope; serialize writes unless isolation is proven.
4. Execute and verify. A model's prose claim is not evidence.
5. On apparent success, invoke `$evidence-gate`. Map every observable goal
   clause to typed evidence and require its `check` command to pass.
6. Only then run `finish --status complete --verification
   "<evidence-gate verification value>" --evidence "<result>"`.
7. Otherwise run `advance --evidence "<result>" --next-action "<next check>"`.
   The script emits `budget_exhausted` when the declared ceiling is consumed.
8. Run `show`; continue only while `terminal_status` is `running`.

While state is `running` and the next action is authorized, begin the next cycle
immediately in the same invocation. Do not yield an intermediate result or ask
again. Yield only for a terminal outcome, user interruption, or real runtime
boundary.

If later evidence contradicts a recorded fact, capture `fingerprint --state
<state-file>`, then use `annotate --expect-sha256 <fingerprint> --evidence
"<correction>"`. Preserve the audit trail; do not reopen terminal state.

Use `finish` for `blocked`, `needs_human`, `cancelled`, or
`continue_scheduled`. Never translate those states or `budget_exhausted` into
`complete`.

After intervention clears a resumable terminal condition, use `resume` to
create a bound successor state, replay the blocked check, and continue while
the successor is `running`. Never reopen the predecessor.

## Preserve durable context

When the installed `worklog` protocol is available, hydrate resume context
before initialization and checkpoint verified state at compaction, delegation,
retry exhaustion, scheduled handoff, or termination. Before cold delegation,
pass the returned `context <slug> --for=compact` pack directly; do not pass the
parent transcript or imply that `spawn` enriches the pack.

For brittle state classification or handoff sequencing, read
[references/examples.md](references/examples.md). Otherwise stay zero-shot.

## Orchestrator mode (multi-task program)

Use when a high-level goal decomposes into 3+ independent tasks managed across
sub-agents. The agent acts as project manager: decompose, dispatch, verify,
track.

**Token efficiency is critical.** This mode is designed for sessions that run
days or weeks. Every token the orchestrator spends on per-task detail is a
token it cannot spend on dispatch. Follow these rules:

- **Evidence in loop_state is one line per cycle.** Just
  `<slug>: claimed → archived`. Per-task evidence lives in worklog task files
  (committed by the sub-agent), not in the orchestrator's memory.
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
  trigger is met; do not preload or invoke it as ceremony. Use the regular loop
  for one or two tasks instead of creating a project.

### Natural language invocation

To invoke this mode, give the agent this prompt:

> Use loop-engineering orchestrator mode. Goal: <goal>.

The agent resolves the rest from the documentation below. No flags, no syntax,
no setup instructions needed. The loop runs until the project queue is empty
(`project next` exits 1), not until a fixed turn count.

### 1. Decompose & budget

Run `$sequential-thinking` only when the task graph is not already explicit or
its dependencies are uncertain. If the user or Worklog already supplies a
clear graph, construct the minimal tasks-json directly. Tasks are independent
unless `depends_on` is set.

Budget is a **safety net**, not a planning constraint. Set it to 999
(effectively unlimited). The real stopping condition is the project queue
emptying: `project next` exits 1 when no eligible tasks remain. The loop
finishes when the queue is empty, not when budget is exhausted.

If decomposition uncertainty is high (ambiguous scope, unclear dependencies,
novel domain), run `$council` to debate the task breakdown before writing.

### 2. Create project

Derive the project slug from the program name, then auto-create child tasks:

```bash
echo '<tasks-json>' | "$WORKLOG_BIN/project.sh" new <slug> \
  --goal="<goal>" --objective="<objective>" --repos=<repo>
```

The tasks-json is the sequential-thinking output mapped to `{slug, kind, depends_on}`.
Each task is one cycle. Budget is set to 999 (safety net; real limit is queue
emptiness, not turn count).

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

Then either:
- **Delegate** to a sub-agent via `task` tool — pass the compact context pack
  directly; do not pass the parent transcript. Instruct the sub-agent to
  commit its evidence, uncertainty, and proposed next action to the worklog
  task file and call `archive.sh`. After that, return exactly one status line:
  `archived <child-slug> <worklog-commit>` (or `blocked|needs_human|failed
  <child-slug> <reason>`); the orchestrator parses that line and discards any
  prose.
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

### 4. Terminal

When budget is consumed or the project queue is empty (`project next` exits 1):

```bash
python3 <skill-dir>/scripts/loop_state.py finish \
  --state <state-file> --status complete \
  --verification "project next exited 1" \
  --evidence "project queue empty: project next exited 1"
```

If the queue still has tasks but budget is exhausted, finish with
`budget_exhausted` and the next eligible task slug.
