---
name: loop-engineering
description: "Run bounded, evidence-driven loops for repeated, resumable, delegated, or scheduled work. Use for iteration toward a verifiable condition, context recovery, subagent coordination, or loop/worklog/scheduler selection. Skip one-shot tasks."
---

# loop-engineering

Use deterministic state transitions around agent judgment. Repeated prompting is not a loop design.

Convention: `$skill-name` means invoke installed skill `skill-name`; skip and record reason if unavailable.

## Route

Use this route matrix before loading references. Read only selected files, once
per unchanged version; do not preload or repeatedly reread the reference tree:

| Signal | Route | Additional context |
| --- | --- | --- |
| one action + one check | one-shot | no loop state |
| fuzzy goal, thin repo, or irreversible effects | interrogate first | load [interrogate.md](references/interrogate.md); init only on a Ready verdict |
| repeated, resumable, or delegated work | driver | one `loop_run.py` call per cycle |
| delegates run concurrently | driver + crew | load [crew.md](references/crew.md); serialize writes unless proven isolation |
| recurrence or installation drift | driver + hosts | load [hosts.md](references/hosts.md); verify host primitive or audit |
| mutation or effect-boundary question | preflight | read [effects.md](references/effects.md) |
| exact transition, worklog, or handoff question | selected route + protocol | load only the needed rules in [protocol.md](references/protocol.md) |

## Compose with installed skills

Use an already-selected owner directly. When choosing another skill, read
[composition.md](references/composition.md) for triggers and compact handoffs.
Do not preload owners. This loop supplies budget/effect/evidence boundaries;
the selected owner supplies its procedure.

## Resolve the skill directory

Use this `SKILL.md` file's directory. Only if the load path is unknown, read
[references/resolvers.md](references/resolvers.md) for the tested host fallbacks.

## Drive the loop — one call per cycle

Invoke with `Use loop-engineering. Goal: <goal>.` — no mode parameters.
The driver wraps `scripts/loop_state.py` and defaults crew/orchestrator mechanics;
do not hand-edit its state JSON.
`<run-dir>/loop_state.json` is the state; `run.json` holds driver configuration.
The displayed budget counts advances; finalizing does not increment it.

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
  toplevel at init), `bin/crew-radar` runs every cycle: `clean|info|warn=<n>`
  are verdicts, `error=` a radar that never ran. Serialize writes (crew.md).
- **Orchestrator, defaulted:** pass `--project <slug>` once for 3+ independently
  dispatched Worklog tasks; the driver reports the next eligible child every cycle
  (orchestrator.md carries the claim/archive rules). `queue: empty|blocked`
  are verdicts; `queue: error=<reason>` is a broken project, not an idle queue.

Override defaults (`--budget`, `--allowed-effect`, `--approval-boundary`, or
raw `loop_state.py` subcommands) only when the run needs it; declare
`--allowed-effect` and `--approval-boundary` whenever writes or external
effects are possible. **Deploys are not tracked here**: nothing observes a
rollout — declare `deploy`, gate with `$evidence-gate`, read CI (crew.md). If `python3` is unavailable, preserve `goal`,
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

Only for delegation with different model needs, read
[composition.md](references/composition.md). Without a usable selector, record
`model-routing: skipped — <reason>`; never claim an unenforced switch.

### Optional payload transport

Only when considering provider/output compression, read
[transport.md](references/transport.md). Missing capability or measured benefit
keeps bytes unchanged; record `pixel-transport: skipped — <reason>`.

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
3. Run the [effect preflight](references/effects.md) for every mutation; if target, authority, or read-only proof is unknown, stop before writing. Name irreversible effects (`merge`, `deploy`, `publish`, secret writes) in `--approval-boundary`, and treat satisfying someone else's armed automation (e.g. an approval releasing a `merge_when_pipeline_succeeds`) as an effect of your own. Serialize writes unless isolation is proven.
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

Probes time out after 10 seconds; timeout/unavailable is an error, not a clean
verdict. Radar shows five warning paths; full results are in
`run-dir/radar-<digest>.json`. `--radar-remote` enables freshness-labelled remote
coverage without fetching, including on later calls. Recover invalid/missing
`run.json` only from a verified copy. Rejected calls do not rewrite it. Do not
run the raw state CLI concurrently with the serialized driver.

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

Use `--stop` for `blocked`, `needs_human`, `cancelled`, or
`continue_scheduled`. Never translate those states or `budget_exhausted` into
`complete`. For corrections or resumption, read [protocol.md](references/protocol.md)
and use the raw state CLI: capture `fingerprint --state <state-file>` before
`annotate --expect-sha256 <fingerprint> --evidence "<correction>"`, or use `resume`.
Preserve the audit trail: corrections append evidence; resumption creates a bound successor and
replays the blocked check. Never reopen terminal state.

## Preserve durable context

Before resuming, delegating, compacting, or checkpointing, read
[references/durable-context.md](references/durable-context.md) for verified
artifact durability, Worklog environment resolution, and compact handoffs.

## Orchestrator mode (multi-task program)

For 3+ independently dispatched Worklog tasks, read
[references/orchestrator.md](references/orchestrator.md) before creating a
project, then pass `--project <slug>` to the same driver. Keep task evidence in
Worklog and the parent history to `claim -> archive -> advance`. Use the regular loop
for one or two tasks. For concurrent delegates, also read
[references/crew.md](references/crew.md); serialize writes unless isolation is proven.
