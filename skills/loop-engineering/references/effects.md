## Effect boundary

Before a mutation, establish its exact target, authorized effect, applicable
approval boundary, and a check for the intended change. Existing authorization
carries forward; routine reversible implementation choices need no repeated
permission. Pause only the affected action if authority or target is unresolved.

Treat merge, deployment, publication, secret writes, and consequential workflow
transitions according to their actual effects. An approval that releases an armed
automation has that automation's effect; inspect it before acting. Honor known
peer constraints and coupled changes. Permission for one surface does not grant
permission for adjacent data or another worker's checkout.

After a timeout or lost response, inspect the target for the intended effect before
retrying. Where the tool supports idempotency, reuse a key for the same authorized
intent, not a hash of regenerated prose. A new agent attempt is not a new intent.
Without tool-side deduplication, reconcile observed state first; unresolved effects
stay unknown and block a blind replay of that mutation.

Batch independent observations; serialize shared mutations under [crew.md](crew.md).
A contradiction stops the affected mutation until the revised approach passes its
discriminating check. The driver records state; it grants no authority and does
not verify external truth, execute actions, dispatch workers, or schedule wakeups.
