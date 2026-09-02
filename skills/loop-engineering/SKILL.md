---
name: loop-engineering
description: "Design and run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled work. Use when iterating toward a verifiable condition, recovering across contexts, coordinating subagents, or deciding on loop vs worklog vs scheduler. Skip one-shot tasks. One invocation, no mode flags: scripts/loop_run.py defaults orchestrator (worklog queue) and crew (conflict radar); the model only decides continue vs stop."
---

# loop-engineering

Use deterministic state transitions around agent judgment. Repeated prompting is
not a loop design.

Convention: `$skill-name` means invoke installed skill `skill-name`; skip and record reason if unavailable.

## When to use

- Agent must iterate toward a verifiable condition
- Recover across context boundaries
- Coordinate subagents
- Decide whether work belongs in a manual loop, worklog-backed handoff, or host-native scheduler
- Multi-task programs with sub-agent dispatch (orchestrator mode)

## Route

1. Skip this skill when one action plus one check is sufficient.
2. For interactive, resumable, or delegated loops, use the driver below —
   one `loop_run.py` call per cycle, no mode parameters.
3. For concurrent delegates or workers, also read
   [references/crew.md](references/crew.md); prove the runtime's isolation or
   keep delegates read-only, and capture `bin/crew-radar` evidence.
4. For scheduled loops or installation drift, also read
   [references/hosts.md](references/hosts.md); require a real recurrence
   primitive for scheduling and use its audit command for duplicate copies.
5. For exact transition, effect, worklog, or handoff rules, read
   [references/protocol.md](references/protocol.md).
6. To re-verify or improve an installed copy of this skill, use the prompt in
   [references/handover.md](references/handover.md).

Use this compact route matrix before loading references:

| Signal | Route | Additional context |
| --- | --- | --- |
| one action + one check | one-shot | no loop state |
| repeated, resumable, or delegated work | driver | one `loop_run.py` call per cycle |
| delegates run concurrently | driver + crew | load crew.md; serialize writes unless proven isolation |
| recurrence or installation drift | driver + hosts | verify host primitive or audit |
| exact transition, effect, worklog, or handoff question | selected route + protocol | load only the needed rules |

## Compose with installed skills

Within a running loop, select the most specific installed owner whose trigger is
true. The owner skill supplies its procedure; loop-engineering supplies the
budget, effect boundary, one-line evidence, and replay check. Do not preload every skill or duplicate an owner's rules. When invoking the owner skill, pass only a compact objective,
known evidence, constraints, budget, and requested return; if no trigger is
true, record `optional-skill: skipped — <reason>` and continue without spending
a cycle.

| Trigger | Owner | Handoff and replay | Skip when |
| --- | --- | --- | --- |
| multi-faceted search across symbols, text, JSON, history, or logs | `$serena-rg-search` | search facet + candidate paths; replay the exact search/history command | one literal or known-file lookup |
| resumability, cross-session context, or a durable handoff is needed | `$worklog` | use `context`/checkpoint rules and return the task or state reference | one-shot work with no durable task |
| actual delegation has materially different model, cost, context, or data-policy needs | `$which-model` | return a model lane and policy gate before dispatch | no delegate surface, or in-band work is sufficient |
| independent results disagree, a counterexample appears, retries fail, or scope/dependencies become ambiguous | `$council` | pass the smallest escalation pack and replay its decision check | clear answer, known trade-offs, or one-shot scope |
| code is written, reviewed, or refactored | `$karpathy-guidelines` | state assumptions, make the smallest change, and replay goal-driven checks | read-only work |
| completion has multiple observable clauses or providers | `$evidence-gate` | map each clause to typed evidence and replay the gate command | one action with one sufficient check |
| a reusable instruction has a brittle format or recurring classification error | `$example-led-instructions` | apply the 0/1/few-shot gate and test the smallest example set | prose is obvious and examples add context cost |
| multiple PRs or stale worklog/PR/CI surfaces need a pre-handoff sweep | `$ship-hygiene` | audit only triggered surfaces and replay the hygiene checks | one short PR with no recent worklog activity |
| one just-finished PR needs learning distillation before handoff | `$tightening-a-pr` | pass the finished diff and task context; replay the handoff checks | implementation is unfinished or the change is trivial |

Routing example: `multi-repo search with uncertain ownership` →
`serena-rg-search` → compact candidate paths plus one replay command;
`one known-file lookup` → `optional-skill: skipped — single literal lookup`.

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. In most
agent contexts, this is the path from which the skill was loaded. If uncertain,
search for `loop_state.py` under the skill root:

```bash
# Claude Code (empty when absent — never a bogus "./.."):
SKILL_DIR="$(f=$(find -L ~/.claude/skills -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$(dirname "$f")")"
# Codex:
SKILL_DIR="$(f=$(find -L ~/.agents/skills -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$(dirname "$f")")"
# Cursor:
SKILL_DIR="$(f=$(find -L ~/.cursor/skills -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && dirname "$(dirname "$f")")"
# Opencode / git worktree (empty outside a repo):
SKILL_DIR="$(r=$(git rev-parse --show-toplevel 2>/dev/null); [ -n "$r" ] && printf '%s' "$r/skills/loop-engineering")"
# Fallback — roots checked in order (a parallel find races -quit across roots):
SKILL_DIR="$(for r in ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills; do f=$(find -L "$r" -name loop_state.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
```

The driver below wraps `scripts/loop_state.py`; every cycle is one call to
`python3 <skill-dir>/scripts/loop_run.py`.

## Drive the loop — one call per cycle

Invoke with `Use loop-engineering. Goal: <goal>.` — no mode parameters.
Orchestrator and crew mechanics are defaulted by the driver; do not hand-edit
its state JSON.

```bash
# First call — auto-initializes a bounded run (default budget 20 turns):
python3 <skill-dir>/scripts/loop_run.py <run-dir> --goal "<observable success condition>"
# Every later call — advance with one typed evidence line, or stop:
python3 <skill-dir>/scripts/loop_run.py <run-dir> --evidence "command: <ref> — <result>"
python3 <skill-dir>/scripts/loop_run.py <run-dir> --stop complete --verification "<gate result>"
```

Each call prints exactly one line with the script-run mechanics folded in:
`running 3/20 turns — next: <action> | radar: clean | queue: <slug> | decide: continue or stop`

- **Crew, defaulted:** when a repo is known (`--repo`, or the cwd's git
  toplevel at init), `bin/crew-radar` runs every cycle and its verdict lands
  in the line. Serialize writes unless isolation is proven (crew.md).
- **Orchestrator, defaulted:** pass `--project <slug>` once when 3+ worklog
  tasks exist; the driver reports the next eligible child every cycle
  (orchestrator.md carries the claim/archive rules).
- **The model decides one thing per cycle:** continue — spend the cycle,
  usually by delegating the queue task — or stop
  (`--stop complete|blocked|needs_human|...`). State, budget, radar, and
  queue are script-run; the decision exists to stop delegating and save
  tokens as soon as the goal or a terminal condition is met.

Override defaults (`--budget`, `--allowed-effect`, `--approval-boundary`, or
raw `loop_state.py` subcommands) only when the run needs it; declare
`--allowed-effect` and `--approval-boundary` whenever writes or external
effects are possible. If `python3` is unavailable, preserve `goal`,
`progress_evidence` (list), `budget` (unit/limit/used), `next_action`, and
`terminal_status` manually in JSON and label the run a non-deterministic
fallback.

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
model. Apply its data-policy gate before delegation.
If no dispatch tool, target skill, or required supporting tool exists, skip
routing and record `model-routing: skipped — <reason>` as one-line evidence;
do not spend a cycle on selection ceremony. If a delegate surface exists but
no model selector does, treat the returned lane as advisory-only and use the
host default; never claim a model switch the harness cannot enforce.

### Optional payload transport

At a provider or tool-output boundary, a capability-gated, fail-open,
recoverable compression (Caveman shrink/Pixel) may be used; read
[references/transport.md](references/transport.md) before doing so. On missing
capability or no measured win, record `pixel-transport: skipped — <reason>`
and pass bytes unchanged.

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
3. Run the protocol's effect preflight (see [references/protocol.md](references/protocol.md)) for every mutation; if target, authority, or read-only proof is unknown, stop before writing. Name irreversible effects (`merge`, `deploy`, `publish`, secret writes) in `--approval-boundary`, and treat satisfying someone else's armed automation (e.g. an approval releasing a `merge_when_pipeline_succeeds`) as an effect of your own. Serialize writes unless isolation is proven.
4. Execute and verify. A model's prose claim is not evidence.
5. On apparent success, invoke `$evidence-gate`. Map every observable goal
   clause to typed evidence and require its `check` command to pass.
6. Only then run `loop_run.py <run-dir> --stop complete --verification "<evidence-gate verification value>" --evidence "<result>"`. This is a terminal outcome — do not continue looping.
7. Otherwise (apparent failure or incomplete) run `loop_run.py <run-dir> --evidence "<result>" --next-action "<next check>"`. The state transitions to `budget_exhausted` when the declared ceiling is consumed.

The driver already emits one index line per call. The `evidence_gate.py` from the
installed `evidence-gate` skill exposes `--quiet` only on `check` and `show`:
redirect successful `init`/`record` stdout to `/dev/null` when compact output is needed,
preserve stderr, and run the final `check` **without** `--quiet` — its index line omits the
verification value step 6 requires. Never trade away exit codes to reduce output.

**Exit codes:** The driver and state CLI exit `0` on success, `2` with a `usage:` error
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

Use `--stop` for `blocked`, `needs_human`, `cancelled`, or
`continue_scheduled`. Never translate those states or `budget_exhausted` into
`complete`. (`fingerprint`, `annotate`, `resume` remain raw `loop_state.py`
subcommands.)

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
the worklog skill's `bin/` directory (`~/.claude/skills/worklog/bin`, `~/.agents/skills/worklog/bin`, or the repo's `skills/worklog/bin`). For an existing task, run
`direnv exec <clone-dir> "$WORKLOG_BIN"/context.sh <slug> --for=resume`, where `<clone-dir>` is the target repo clone whose `.envrc` sets `WORKLOG_REPO`, so the target clone's direnv variables are active; if `direnv` is absent, run `context.sh` directly and label the run `worklog-checkpoint: unavailable — local fallback`.
Before cold delegation, pass the returned
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

No separate invocation exists: the same `Use loop-engineering. Goal: <goal>.`
plus `--project <slug>` on the driver engages it.

For concurrent delegates or isolated worktree workers, read
[references/crew.md](references/crew.md) — orchestrator mode plus capability-gated concurrency.
