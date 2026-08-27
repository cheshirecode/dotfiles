---
name: loop-engineering
description: "Design and run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled engineering and research work. Use when an agent must iterate toward a verifiable condition, recover across context boundaries, coordinate subagents, or decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler. Skip trivial one-shot tasks. Orchestrator mode: use for multi-task programs with sub-agent dispatch."
---

# loop-engineering

Use deterministic state transitions around agent judgment. Repeated prompting is
not a loop design.

## Route

1. Skip this skill when one action plus one check is sufficient.
2. For interactive, resumable, or delegated loops, use the state script below.
3. For concurrent workers in separate worktrees, also read
   [references/crew.md](references/crew.md); arm `bin/crew-radar` before the
   first parallel dispatch.
4. For scheduled loops or installation drift, also read
   [references/hosts.md](references/hosts.md); require a real recurrence
   primitive for scheduling and use its audit command for duplicate copies.
5. For exact transition, effect, worklog, or handoff rules, read
   [references/protocol.md](references/protocol.md).

Use this compact route matrix before loading references:

| Signal | Route | Additional context |
| --- | --- | --- |
| one action + one check | one-shot | no loop state |
| repeated, resumable, or delegated work | state CLI | initialize a bounded run |
| tasks run concurrently in separate worktrees | state CLI + crew | prove isolation, then arm the conflict radar |
| recurrence or installation drift | state CLI + hosts | verify host primitive or audit |
| exact transition, effect, worklog, or handoff question | selected route + protocol | load only the needed rules |

## Compose with installed skills

Within a running loop, select the smallest installed owner whose trigger is
true. The owner skill supplies its procedure; loop-engineering supplies the
budget, effect boundary, one-line evidence, and replay check. Do not preload
every skill or duplicate an owner's rules. Pass only a compact objective,
known evidence, constraints, budget, and requested return; if no trigger is
true, record `optional-skill: skipped — <reason>` and continue without spending
a cycle.

| Trigger | Owner | Handoff and replay | Skip when |
| --- | --- | --- | --- |
| multi-faceted search across symbols, text, JSON, history, or logs | `serena-rg-search` | search facet + candidate paths; replay the exact search/history command | one literal or known-file lookup |
| resumability, cross-session context, or a durable handoff is needed | `worklog` | use `context`/checkpoint rules and return the task or state reference | one-shot work with no durable task |
| actual delegation has materially different model, cost, context, or data-policy needs | `which-model` | return a model lane and policy gate before dispatch | no delegate surface, or in-band work is sufficient |
| a compact context pack or payload transport gate is needed and the helper is installed | `loop-helpers` | pass explicit fields or gate facts; replay the helper command | no helper install, or ordinary context is sufficient |
| independent results disagree, a counterexample appears, retries fail, or scope/dependencies become ambiguous | `council` | pass the smallest escalation pack and replay its decision check | clear answer, known trade-offs, or one-shot scope |
| code is written, reviewed, or refactored | `karpathy-guidelines` | state assumptions, make the smallest change, and replay goal-driven checks | read-only work |
| completion has multiple observable clauses or providers | `evidence-gate` | map each clause to typed evidence and replay the gate command | one action with one sufficient check |
| a reusable instruction has a brittle format or recurring classification error | `example-led-instructions` | apply the 0/1/few-shot gate and test the smallest example set | prose is obvious and examples add context cost |
| multiple PRs or stale worklog/PR/CI surfaces need a pre-handoff sweep | `ship-hygiene` | audit only triggered surfaces and replay the hygiene checks | one short PR with no recent worklog activity |
| one just-finished PR needs learning distillation before handoff | `tightening-a-pr` | pass the finished diff and task context; replay the handoff checks | implementation is unfinished or the change is trivial |

Routing example: `multi-repo search with uncertain ownership` →
`serena-rg-search` → compact candidate paths plus one replay command;
`one known-file lookup` → `optional-skill: skipped — single literal lookup`.

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

Keep transient loop state and verbose evidence out of the skill or repository
worktree. Use `/tmp`, `$TMPDIR`, or another host-provided system temporary
directory for state files, evidence-gate JSON, logs, and snapshots (for example,
create a directory with `mktemp -d`). Only intentional source, documentation,
tests, and explicitly authorized durable artifacts belong in the worktree; do
not leave ad hoc run artifacts behind.

### Optional model routing

For a non-trivial loop, invoke `$which-model` before dispatch only when the
current harness exposes it and the task has materially different capability,
context, privacy, or cost needs. Ask for a model lane, not an unverified exact
model. Apply its data-policy gate before delegation. If there is no dispatch,
the skill is unavailable, or a required supporting tool is unavailable, skip
routing and record `model-routing: skipped — <reason>` as one-line evidence;
do not spend a cycle on selection ceremony.

### Optional payload transport

At a provider or tool-output boundary, choose a capability-gated,
fail-open, recoverable representation. Measure after selection; if the result
is not smaller or legible, send the original bytes.

1. For noisy command output or tool catalogs, an authorized Caveman install may
   use `caveman shrink -- <command>` before Pixel. Preserve producer status with
   `set -o pipefail`; keep the original in CCR and retain its recovery handle.
   Do not install an output-only response skill for input savings: it can add
   prompt overhead while leaving provider input unchanged.
2. Use [Caveman Pixel Mode](https://github.com/juliusbrussee/caveman#pixel-mode)
   only for dense, long-line payloads, with a legible model and a measured win
   before `caveman wrap --pixel <agent>`. Never pixel sparse code, normal
   Markdown, loop state, evidence, diffs, or small payloads.
3. For installed skill bodies, use `caveman convert --dry-run` first and convert
   only profitable installed copies; keep frontmatter text, preserve the
   byte-identical `--revert` path, and never rewrite canonical source here.
4. Check `command -v caveman` and authorization first. On missing capability,
   decline, failure, or recovery/verification trouble, record
   `pixel-transport: skipped — <reason>` and pass bytes unchanged.
5. Label token/size estimates `inferred`; call them `verified` only after real
   traffic and an evaluation gate. Do not install Caveman or change agent
   configuration unless the effect boundary authorizes it.

One compact example: `dense long-line log + authorized CLI + measured win` may
use shrink or Pixel; `sparse code`, missing CLI, or no win keeps the original.

### Compaction-friendly output

Default loop updates are action-first and bounded: put `state` and the one next
action first, number multi-step work, cap lists at five items, and omit
preambles, tangents, and recap prose. Keep detailed findings in the typed
state/worklog artifact; the visible update is only the index. This shapes the
conversation without replacing evidence, verification, or a user's request
for a full explanation.

Use simple technical English: short sentences, concrete verbs, and minimal
jargon; define unavoidable acronyms once. Remove hype, idioms, filler, repeated
summaries, and process chatter. Preserve exact commands, paths, identifiers,
errors, and typed evidence.

## Run one bounded cycle

1. Observe from tools or durable evidence.
2. Choose the smallest action that advances or falsifies the approach.
3. Run the protocol's effect preflight for every mutation; if target, authority,
   or read-only proof is unknown, stop before writing. Serialize writes unless
   isolation is proven.
4. Execute and verify. A model's prose claim is not evidence.
5. On apparent success, invoke `$evidence-gate`. Map every observable goal
   clause to typed evidence and require its `check` command to pass.
6. Only then run `finish --status complete --verification
   "<evidence-gate verification value>" --evidence "<result>"`.
7. Otherwise run `advance --evidence "<result>" --next-action "<next check>"`.
   The script emits `budget_exhausted` when the declared ceiling is consumed.
8. Run `show`; continue only while `terminal_status` is `running`.

Keep each evidence value to one typed line: `kind: reference — result`, where
`kind` is `command`, `artifact`, `git`, `github`, or `url`. Store verbose
output in the referenced artifact and keep loop state as an index, not a log.

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
retry exhaustion, scheduled handoff, or termination. For an existing task, run
`$WORKLOG_BIN/context.sh <slug> --for=resume` from the target clone's direnv
context before initializing state. Before cold delegation, pass the returned
`context <slug> --for=compact` pack directly; do not pass the parent transcript
or imply that `spawn` enriches the pack. If Worklog or its environment is not
available, use the explicit state path plus one authorized artifact and label
the run `worklog-checkpoint: unavailable — local fallback`.

Pack before compaction: pass only the objective, known evidence, constraints,
budget, requested return, and recovery handles. Keep raw output in system temp
or CCR; never rebuild a handoff by replaying the parent transcript.

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
- **Bulk generation offloading.** Never generate $\ge 3$ repetitive structured files
  or template expansions in-band on frontier orchestrator tokens. Prepare a compact
  spec pack and delegate generation to a low-cost sub-agent (`mechanical` / utility model)
  to cut generation token costs by $>85\%$.
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

When the tasks must run at the same time in separate worktrees, read
[references/crew.md](references/crew.md) — same queue, budget, and evidence
rules, plus isolation and the conflict radar.

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

Budget is a **safety net**, not a planning constraint, only when the user has
not supplied a ceiling. If the user gives a budget, use that exact limit; never
silently replace it with 999. If the user gives both a minimum cycle count and
a ceiling, record the minimum in the goal and do not finish before that minimum
is met, even if the queue empties. Otherwise, use 999 as the default safety net
for a project whose real stopping condition is the queue emptying:
`project next` exits 1 when no eligible tasks remain.

If decomposition uncertainty is high (ambiguous scope, unclear dependencies,
novel domain), run `$council` to debate the task breakdown before writing.

### Mid-run council escalation

An authorized orchestrator may invoke `$council` without a new user turn when a
running program crosses a material uncertainty trigger: independent task
returns disagree, a material counterexample appears, bounded retries fail, or
the task graph or scope becomes ambiguous. Pause only the affected mutation,
pass the council the original goal plus compact context and evidence, and do
not pass the full parent transcript.

Use the smallest escalation pack: `trigger`, `affected mutation`, `one decision
question`, `evidence`, and `replay check`. Accept only `verified` or
`UNVERIFIED` plus a decision; a verified result must pass the replay check
before the task resumes.

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

The tasks-json is the sequential-thinking output mapped to `{slug, kind, depends_on}`.
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

When budget is consumed or the project queue is empty, capture the complete
`project next` result and verify the project before finishing. Exit 1 alone is
not proof of an empty queue: it also covers blocked or missing children. Treat
the queue as empty only when `project next` reports `all tasks ... are archived
(nothing left)` and `project verify <slug>` exits 0:

```bash
next_output="$($WORKLOG_BIN/project.sh next <program-slug> 2>&1)" || true
if ! grep -Fq "all tasks for '<program-slug>' are archived (nothing left)" <<<"$next_output"; then
  echo "$next_output" >&2
  exit 1
fi
if ! $WORKLOG_BIN/project.sh verify <program-slug>; then
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
