# Metric-gated experiment loops

Use when many small trials compete on one number: tuning, optimization, prompt
or model search, benchmark work. Each trial changes the code, runs one fixed-cost
measurement, and is kept or discarded by that number. Skip when no single
comparable metric exists; use the ordinary driver cycle instead.

## Fix the metric and the trial cost first

Name one metric and its direction before trial one. Put it in the goal. A run
with two metrics has no keep rule.

Give every trial the same cost ceiling — wall time, tokens, rows, or steps.
Equal cost is what makes two trials comparable, and it removes cost from the
decision. Record which resource you fixed; a metric is only comparable against
trials that paid the same price.

Name secondary limits (memory, latency, index size) as soft constraints. State
the ceiling. A large gain may buy some growth; unexplained growth is a discard.

Trial one changes nothing. It records the baseline. Without that row, no later
number means anything.

## One change per trial

Change one thing. Commit it before the run. That commit is the trial identity.
A trial that bundles two changes cannot say which one moved the number.

## Keep or discard by the number

| Result | Action |
| --- | --- |
| Metric improved, complexity flat or lower | Keep. The branch advances to this commit |
| Metric improved a little, much more code | Discard. Weigh the added lines against the gain |
| Metric equal, less code | Keep. Deleting code for the same result is a win |
| Metric equal, same or more code | Discard |
| Metric worse | Discard, whatever the code size |

Run trials in a dedicated worktree on a dedicated branch, never in a checkout
another session may use. That worktree is disposable, which is what makes a
discard cheap.

Discarding means `git reset --hard <baseline-sha>`, and that command destroys
uncommitted work. Run it only when all three hold: the worktree is the trial's
own, the trial commit is unpushed, and the tree holds nothing but the trial. A
pushed trial is reverted, not reset. If any condition is unclear, delete the
worktree and cut a fresh one from the baseline instead — same result, nothing
destroyed. The [effect boundary](effects.md) governs this like any other
mutation, and a project rule that gates `--hard` still gates it here.

## Read the metric, not the log

Redirect each trial to a log file in `<run-dir>`. Do not tee it and do not
stream it into context; one flooded trial ends the run.

Extract the metric with an anchored pattern (`grep "^val_bpb:" run.log`). An
unanchored pattern can match a nested field and report a confident wrong value.

An empty extraction means the trial failed. It is not a score of zero, and a
successful `grep` or `tail` says nothing about the trial that wrote the log —
[protocol.md](protocol.md#verifying-a-claim) owns that rule; capture the trial's
exit status alongside the metric. Then read the tail of the log and classify: a
typo or missing import is worth one fix and one rerun; a broken idea is recorded
as a crash and left. Bound the fix attempts.

Set a kill ceiling before trial one, and set it on the trial's whole observed
duration, not on the fixed inner budget. The two differ: autoresearch fixes five
minutes of training but kills at ten minutes of total runtime, because startup,
compilation and evaluation sit outside the budget. A ceiling of twice the
expected total is a reasonable default. A trial that hits it is a failure, not a
score.

## Keep a ledger of every trial

One row per trial: commit, metric, secondary limit, status (`keep`, `discard`,
`crash`), and a one-line description. Use tabs, so a comma in the description
cannot split a column.

Record crashes too. A missing row invites the same failing idea again.

Keep the ledger untracked and inside `<run-dir>`. Committing it puts the results
into every trial diff, and a discard reset then destroys the results themselves.

## Autonomy inside the declared budget

Do not pause between trials to ask whether to continue. The user may be away,
and an idle question wastes the whole window.

The declared budget still ends the run, and an unresolved effect still stops at
its boundary. This is where the adopted loop differs from its source: the source
runs until a human interrupts it. Here the ceiling ends it as
`budget_exhausted`, with the best commit and the ledger path as evidence.

Running out of ideas is not a stop. Re-read the in-scope files, combine two near
misses, read the sources the code cites, or try one larger change.

## Map to the driver

One trial is one advance. Record it as
`command: <trial command> — <metric>=<value> <status>`. Stop `complete` when the
metric target is met and the evidence gate passes; the accepted commit and the
ledger are the artifacts.

This adapts [karpathy/autoresearch's `program.md`](https://github.com/karpathy/autoresearch/blob/228791fb499afffb54b46200aca536f79142f117/program.md)
from its single-GPU training loop to this skill's budget, effect and evidence
rules.
