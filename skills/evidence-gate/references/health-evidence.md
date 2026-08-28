# Health evidence

**Evidence of a change is not evidence of its health.** A verified diff proves
the change is what you think it is; it says nothing about whether it works. Any
clause asserting readiness, mergeability, or a successful rollout needs a second,
separate piece of typed evidence for health — the CI verdict at the head SHA for
an MR, the canary verdict for a deploy. Observed 2026-08-28: an MR re-approved on
a correctly-read diff while its pipeline was red with 28 errors.

Health evidence must also **span the failure period**, not merely measure the
right quantity. A check whose window is shorter than the period of an
intermittent failure returns clean and means nothing. Measured the same day: a
crossed auth pairing failing on a ~15-minute cache clock read 180/180 clean over
one short run and 38/360 (~10.6%) over a run crossing four cache boundaries —
same system, opposite verdicts.
