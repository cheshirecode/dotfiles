# Definition of done and acceptance

Use before substantive implementation or delegation, and when accepting a result.
Keep the record in the task or run artifact; do not add a new state schema.

## Form an expectation

Use the user's request and current system behavior to define:

- The observable outcome and relevant behavior that must remain intact.
- Expected results, failure conditions, and checks at the actual target boundary.
- The accepting owner, permitted effects, and requested delivery stage.

Set these before reading the generated solution or delegate's return. A simple
task needs only one outcome and its check. Use existing project checks where
they answer the requirement. Resolve material unknowns through
[plan readiness](interrogate.md); do not require a questionnaire for clear work.

If a generated proposal is already visible, record that exposure rather than
inventing a prior expectation. Build the checks from the user's requirements and
independent source or runtime evidence before further work.

## Keep ownership of the decision

For an unfamiliar component or consequential design choice, inspect the decisive
source or runtime behavior before accepting a proposed mechanism. Record the
relevant assumption, expected failure behavior, and concise reason for the choice.
Use conceptual questions to fill a knowledge gap before requesting more code.
Do not request private reasoning transcripts or claim a user understands a change
because an agent supplied an explanation.

Keep the declared checks stable while evaluating the candidate. A changed
requirement needs its reason and authority recorded, then affected checks rerun.
A persuasive explanation, passing unrelated tests, or reviewer agreement cannot
resolve an observation that contradicts the requirement. Follow the
[replan rule](interrogate.md#replan) for that contradiction.

## Review a specific question

Complete reviews required by the user or repository. Add optional review only
for a concrete unresolved risk, assumption, or disagreement. State the question
and the evidence that would settle it; bound the attempt and stop when answered.
Do not start a critique wave when the declared checks already establish done.

## Accept against the contract

The accepting owner checks the change, its mechanism, and whether evidence proves
each declared outcome at the current revision. If a critical
part cannot be explained, inspect that part or run a discriminating check.
Then use the evidence gate. Its coverage result cannot make this decision.
Leave an unmet outcome unverified and name the next resolving action.

This applies [Cognitive Surrender](https://addyosmani.com/blog/cognitive-surrender/)
to the existing loop: establish expectations before generation, retain the
decision, and finish on relevant evidence. It is workflow guidance, not a claim
that agent checks measure a human's understanding.
