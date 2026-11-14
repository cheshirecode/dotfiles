# Context budget

A long session ends one of two ways: the work finishes, or the context fills and
the session loses the thread. The second failure is avoidable, and it is caused
almost entirely by what the agent reads, not by what it writes. Treat remaining
context as a declared resource, like turns.

## Bound every read before you run it

Decide the shape of the output before running the command, not after reading it.
Three moves cover nearly every case:

- **Page it.** `sed -n '400,480p'`, `head`, `git log -n 20`, a tool's `--limit`.
- **Filter it.** Grep for the lines that answer the question asked.
- **Cap it.** Redirect the whole output to an artifact in `<run-dir>`, then read
  the slice you need. The artifact keeps the evidence; context gets the answer.

Anthropic's architecture guidance recommends pagination, range selection,
filtering and truncation with sensible defaults, and suggests "something like
25,000 tokens" as a manageable ceiling for one response. Treat that as a
reference point, not a measured limit: the asymmetry is what matters, because a
session absorbs many small responses and dies to a few large ones.

Redirect first, read second, whenever the output size is not predictable — log
tails, full test suites, `git log` with no count, directory walks, network dumps.
Slicing a file is cheap and repeatable. An unbounded read cannot be undone.
Preserve the producer's exit status when slicing or piping;
[protocol.md](protocol.md#verifying-a-claim) owns that rule.

Return the producer's exit status, result counts, relevant failures and the
artifact path. State what was omitted; retrieve more when diagnosis or an
acceptance check needs it. A host's tool-history cap can bound retained output,
but cannot recover bytes that were never saved. Choose caps as workload trials,
not model-specific constants, and keep full evidence outside the prompt.

## Prefer the answer to the material

Let the tool compute what you need. Count with `wc -l` or a `--count` flag rather
than reading rows and counting them. Ask a search for `file:line` locations, then
open only the lines that matter. Compare with a checksum or a diff exit status
rather than by reading both versions.

Delegate a broad sweep when you want the conclusion and not the material. The
delegate's reads land in its context; only its return lands in yours. That is the
context argument for fan-out, and it is separate from the cost argument in
[crew.md](crew.md#ownership-and-dispatch), which still governs when to dispatch.

## Check every work boundary

At start, after each tool batch or delegate wave, and before switching
between orchestration and implementation, run:

```bash
# Set these from observed batches/waves and the last verified checkpoint.
python3 <skill-dir>/scripts/context_guard.py \
  --session-units "${SESSION_UNITS:?set observed session units}" \
  --since-checkpoint "${SINCE_CHECKPOINT:?set observed units since checkpoint}"
```

One unit is one completed tool batch or delegate wave, including failed attempts.
Record the counters in the task checkpoint. Do not wait for accepted results.
Pass `--role-switch` before changing roles and `--read-truncated` after unexpected
host truncation. A deliberate excerpt of a saved log is not a truncated read. Add `--context-pct N` only from current host telemetry. Account usage limits
and the agent's intuition do not measure the session window. Missing telemetry
stays `unknown`; unit limits still apply.
For an existing long session with unknown counters, pass `--history-unknown`.
Do not invent a zero count to keep working.

| Decision | Trigger | Required action before more task work |
| --- | --- | --- |
| `continue` | No boundary reached | Execute the next bounded unit |
| `checkpoint` | Three units since checkpoint, or role switch | Save and read back the task checkpoint and recovery locator |
| `handoff` | Eight session units, measured context at least 50%, unexpected truncation, or unknown prior history | Checkpoint, verify recovery, then reset context or transfer ownership |

Exit 0 means continue, 1 requires the named action, and 2 rejects invalid input.
The helper is stateless. It neither reads host usage nor writes Worklog, changes
loop status, resets context, or creates sessions. The agent must honor its result.
These thresholds are conservative workload defaults, not measured model limits.
Honor a stricter user budget. The optional driver's `--context-pct` is only a
display; it does not replace this boundary check.

## Save, verify, then reset

Keep only the goal, acceptance checks, authority, current source identity,
unresolved next action, and [recovery locator](durable-context.md#recovery-locator)
in active context. Put decisions and accepted results in the existing Worklog
task. Keep large logs and diffs in durable artifacts linked from that task.
Workers return status and evidence references; the parent retrieves only decisive
parts. When the orchestrator implements code, finish and check one bounded unit
before returning to orchestration. It does not reload each worker's full investigation.

Read back the saved checkpoint through the Worklog owner. Build the existing
bounded compact pack, then test that its locator retrieves the goal, constraints,
source identity, remaining budget, and next check. A fresh reader can perform this
test without the parent transcript. A missing, stale, or unreadable checkpoint
blocks reset; repair its recovery path first. Only a verified checkpoint resets
`since-checkpoint`. Writing notes alone does not reset `session-units`.

Use a supported host compaction operation if available. Otherwise transfer the
same work order to a fresh session only with the required user authorization.
Record host reset capabilities and any automatic-continuation authorization at
intake. A skill cannot grant permission to create tasks on the user's behalf.
Pass the compact pack and locator, not the old transcript or a full-history fork.
The predecessor stops task mutations after the successor accepts ownership.
Finished work needs its final report, not a fresh session.
If no reset or authorized transfer is available, report that boundary and the
ready handoff. Do not claim that a summary deleted old context.

After a real reset, recover from the locator and replay the next health check
before editing. Reset session counters only after that recovery succeeds.
Do not delete global memories, task history, or evidence to reduce active context.

This combines structured notes, compaction, and focused delegates from
[Anthropic's context guide](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents)
with the host-managed session boundary described in
[OpenAI's session guide](https://developers.openai.com/cookbook/examples/agents_sdk/session_memory).

## Keep the loop's own state small

State is an index, not a log — the root skill already says so, and the context
budget is why. One typed evidence line per cycle points at an artifact that holds
the volume. Evidence lines that carry pasted output turn the state file itself
into a second context problem on resume.

When installed, `loop-helpers/scripts/context_pack.py` enforces a serialized
byte budget and rejects oversized packs without dropping fields. Replace raw
evidence with recovery references before retrying. Preserve decisions, user
corrections and authorization boundaries; a small JSON encoding alone does not
make a handoff bounded.

## Verify a saving

Separate emitted payload size, provider input/cache/output usage and billed cost.
Historical sink estimates can overlap; a new scan after a setting change does
not establish causality. Compare matched tasks at the same model and effort,
including summary generation, recovery reads, retries and acceptance results.
Smaller output is useful only if required evidence remains recoverable and the
task still passes its checks. Label byte measurements as bytes, and leave token
or cost savings unverified when provider measurements are unavailable.

This applies the context-management guidance in Anthropic's
[Building Effective AI Agents: Architecture Patterns and Implementation Frameworks](https://resources.anthropic.com/hubfs/Building%20Effective%20AI%20Agents-%20Architecture%20Patterns%20and%20Implementation%20Frameworks.pdf)
to this skill's budget and evidence rules.
