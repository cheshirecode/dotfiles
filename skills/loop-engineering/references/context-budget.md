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

## Track consumption, not only turns

A turn budget does not measure context. Turns count recorded advances, not bytes
read, so two loops at the same turn count can consume very different amounts —
one cycle that reads a whole test log outweighs many that read a grep result.

Pass `--context-pct <n>` on each cycle. The driver records it and prints
`context: n%`, adding `OVER — checkpoint and hand off` at 50 or above. Half the
window is where answers degrade and the cached prefix stops being reused: a
local scan of 77461 turns found 21472 past that line, the largest single penalty
in that report, against ~1 point for the whole always-loaded prefix. The driver
cannot read the harness's usage, so the figure comes from the agent; omitting it
changes nothing.

Hand off before forced compaction, not after. A checkpoint you write keeps the
evidence you chose; a compaction the host runs keeps what the host chose. When
the remaining context would not cover one more cycle *and* its verification,
checkpoint with the [compact pack](durable-context.md#compact-pack) and continue
in a fresh session. Stopping at `continue_scheduled` or another resumable
terminal state with a written pack beats being truncated mid-cycle.

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
