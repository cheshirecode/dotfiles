## Effect boundary

- Declare allowed effects and the approval boundary at initialization when
  files, external systems, or user data may change.
- Parallelize independent read-only observations.
- Serialize writes unless the runtime proves isolation.
- After a contradiction, stop affected mutations, revise the hypothesis, and
  replay the original discriminating check.

Before every mutation, run this effect preflight:

1. What exact path, provider, or person can this action affect?
2. Is that target listed in `allowed_effects`?
3. Does the action cross `approval_boundary` or require a new authority?
4. What read-only check will prove that the intended target, and no adjacent
   target, changed?
5. Is the action reversible? Name the irreversible ones in
   `approval_boundary` — merge, deploy, publish, a secret write, a ticket
   transition — and re-read that list here. Questions 1-4 treat every write
   alike, so an authority to comment reads as an authority to merge unless the
   boundary says otherwise.
6. Does the action *satisfy someone else's armed automation*? An approval that
   releases an armed `merge_when_pipeline_succeeds` merges the MR; you did not
   call merge, you supplied its last condition. Check the flag before any action
   whose completion you would not be permitted to perform directly.
7. Has another session declared a constraint on this artifact? Authority
   settles whether you *may* act; it does not tell you whether you *should*.
   Read the owning task's notes before an irreversible action, even when every
   mechanical signal is green. Verified 2026-08-28: an MR was approved,
   mergeable, threads resolved and authored by the acting identity — and
   merging it alone would have moved production onto a broken auth pairing,
   because the code change had to land in the same deploy as a secret rotation.
   No API field carried that; it existed only in a peer's worklog task.

If any answer is unknown, stop before the write and narrow the action or end
`needs_human` with the missing authority named.

The script records state; it never grants permission, executes the action,
verifies external truth, delegates, or schedules a wakeup.
