# Definition of done and acceptance

Record the contract in the task or run artifact before substantive work.
Use the existing state schema when a durable driver is active.

## Form an expectation

From the user's request and current behavior, define:

- Outcome, behavior to preserve, expected results, and failure conditions.
- Checks at the actual boundary, accepting owner, permitted effects, and delivery stage.

Set these before reading generated solutions or worker returns. Simple work needs
one outcome and check. Reuse relevant project checks; [plan readiness](interrogate.md)
handles material unknowns without adding a questionnaire to clear work.

If a generated proposal is already visible, record that exposure rather than
inventing a prior expectation. Build the checks from the user's requirements and
independent source or runtime evidence before further work.

## Keep ownership of the decision

For unfamiliar or consequential mechanisms, inspect decisive source or runtime
behavior. Record the assumption, failure behavior, and concise reason for the
choice. Resolve knowledge gaps before requesting more code. An agent's explanation
does not establish the user's understanding.

Keep checks stable during evaluation. Record the reason and authority for changed
requirements, then rerun affected checks. Contrary observations require
[replanning](interrogate.md#replan); persuasion, unrelated tests, and reviewer
agreement cannot settle them.

## Review a specific question

Complete required reviews. Optional review needs a concrete unresolved question,
settling evidence, and bounded attempt. Stop when answered; add no critique wave
when the declared checks establish done.

## Accept against the contract

The owner checks the change, mechanism, and evidence for every outcome at the
current revision. Inspect or test critical parts that cannot be explained.
Use the evidence gate for multiple completion criteria; coverage cannot make
the acceptance decision.
Unmet outcomes remain unverified with a resolving next action.

Adapted from [Cognitive Surrender](https://addyosmani.com/blog/cognitive-surrender/):
retain expectations, decisions, and evidence. Agent checks do not measure human understanding.
