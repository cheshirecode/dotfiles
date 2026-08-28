---
name: loop-engineering
description: "Design and run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled engineering and research work. Use when an agent must iterate toward a verifiable condition, recover across context boundaries, coordinate subagents, or decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler. Skip trivial one-shot tasks. Orchestrator mode: use for multi-task programs with sub-agent dispatch. Crew mode: use when workers must run in parallel across git worktrees, or to detect two worktrees changing the same file."
---

# loop-engineering

Use deterministic state transitions around agent judgment. Repeated prompting is
not a loop design.

## When to use

- Agent must iterate toward a verifiable condition
- Recover across context boundaries
- Coordinate subagents
- Decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler
- Multi-task programs with sub-agent dispatch (orchestrator mode)

Skip if: one action plus one check is sufficient (trivial one-shot tasks).

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

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. In most
agent contexts, this is the path from which the skill was loaded. If uncertain,
search for `loop_state.py` under the skill root:

```bash
SKILL_DIR="$(dirname "$(find ~/.claude/skills -name loop_state.py -print -quit 2>/dev/null)")/.."
# Or, if the skill is in the current repo:
SKILL_DIR="./skills/loop-engineering"
```

All script invocations below use `python3 <skill-dir>/scripts/loop_state.py`.

## Initialize through the script

Choose an explicit, authorized state path; do not hand-edit its JSON.

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
effects are possible. If `python3` is unavailable, preserve these five fields
manually in a JSON file and label the run as a non-deterministic fallback:
`goal`, `progress_evidence` (list), `budget` (unit/limit/used), `next_action`,
and `terminal_status`.

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

Pass `--quiet` to every `loop_state.py` and `evidence_gate.py` call. Without it
they print the whole state document, history included, so the output grows each
cycle and contradicts the compaction rule above; `--quiet` emits the index line
those rules ask for (`running 3/12 turns — next: <action>`, `satisfied 4/4`) and
leaves exit codes unchanged.

**Exit codes:** The state CLI exits `0` on success, `2` with a `usage:` error
for malformed CLI usage, and `3` with a `loop-state:` error when the state
contract rejects the transition. See
[references/protocol.md](references/protocol.md) for transition rules.

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

**Uncommitted working-tree state is not durable state.** A checkpoint records
that work exists; it does not make it exist. Commit and push before any
checkpoint claiming an artifact, and confirm with `git ls-remote` — local
`git log` only proves the commit reached this machine, and a forge API can serve
a stale head SHA. Observed 2026-08-28: worktree fixes checkpointed, instance
died, record survived, work did not.

When the installed `worklog` protocol is available, hydrate resume context
before initialization and checkpoint verified state at compaction, delegation,
retry exhaustion, scheduled handoff, or termination. Resolve `$WORKLOG_BIN` to
the worklog skill's `bin/` directory (e.g., `~/.claude/skills/worklog/bin` or
the repo's `skills/worklog/bin`). For an existing task, run
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

Use when a high-level goal decomposes into 3+ independent tasks dispatched across
sub-agents, and the agent acts as project manager: decompose, dispatch, verify,
track. Token efficiency is the whole design — the orchestrator's own history must
stay a repeating `claim X -> archive X -> advance` pattern, with per-task evidence
in worklog task files rather than in its context.

Read [references/orchestrator.md](references/orchestrator.md) before creating a
project; it carries the decomposition, queue, cycle, and terminal rules. Use the
regular loop for one or two tasks instead of creating a project.

Invoke it with: `Use loop-engineering orchestrator mode. Goal: <goal>.`

For workers running concurrently in separate worktrees, read
[references/crew.md](references/crew.md) — orchestrator mode plus isolation.
