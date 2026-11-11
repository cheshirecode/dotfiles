# Local ledger contract

Run `python3 <skill-dir>/scripts/watch.py --state <private-directory> init --input config.json`.
Apply events with `apply --input event.json`; `show` prints counts and control state.
Each apply is one locked, atomic transaction. A rejected event leaves the ledger
unchanged. The helper never invokes Slack, Git, a browser or a scheduler.

Minimum configuration (replace the example scope and authorization with the user's):

```json
{
  "workspace": "example-workspace", "channel": "CEXAMPLE", "thread_ts": "1700000000.000001",
  "scope": "Repair the named PR within the user's approved repository and preview environment",
  "stop_condition": "Until user says stop, subject to this run budget",
  "cadence_seconds": 60, "max_polls": 10, "run_seconds": 1800,
  "writes": {}
}
```

Omit write capabilities unless explicitly authorized. For authorized actions,
`writes` can contain `reaction` and/or `post`, each with the user's authorization
text as its value. A successor directory requires explicit budget renewal and a
link to the preceding ledger; do not reset counters in place.

## Events

All timestamps are Slack decimal **strings**, never floating-point numbers.
The helper's observed cursor is the highest message timestamp from a complete
read. It is not a provider page cursor or proof that the messages were acted on.
Store continuation pages privately during collection; a resumed incomplete poll
can restart collection from the root under the same reservation.

- `{"type":"poll-start"}` reserves one bounded poll. A second reservation fails
  until its result or failure is recorded.
- `poll-result` needs `complete: true`, `next_cursor: ""`, an `anchor` matching
  workspace/channel/thread_ts, and `messages: [{"ts":"...","content":"..."}]`.
  Normalize the connector's actual responses; do not feed a truncated response
  or pretend an unsupported provider pagination field exists. `content` includes
  text, stable file/attachment identifiers, and edit timestamp when available;
  exclude volatile reactions and counters. Include the root. Do not claim file
  contents were read merely because a file identifier was ingested.
- `poll-failed` needs `error`; optionally `retry_after_seconds` from the provider.
  It preserves the observation cursor and sets exponential backoff. Three
  consecutive failures pause the watch. Record interrupted attempts this way
  if abandoning their collection. A timeout is not an empty successful read.
- `read` needs `message_ts`, its current `revision` hash from `state.json`, and
  optionally a `disposition`. This means the agent actually read the content.
- `case` needs a stable `id`, `message_ts`, current `revision`, `stage`, and an
  `evidence` reference. A new case also needs `given`, `when`, `then` strings.
  Stages: `mapped`, `implemented`, `deployed`, `verified`, `failed`.
  Implemented/deployed/verified need a full 40-character Git `commit`.
  Deployed/verified need `deployed_commit` equal to that commit. Verification
  also needs an earlier deployed entry for that commit. The agent must inspect
  the actual URL and test artifacts: matching strings alone prove no health.
  Record failed BDD output/screenshots as `failed` attempts, never overwrite them.
  Edited messages supersede all previous cases for that message. Create new IDs
  for its new revision; retain the old case attempts. A failed attempt at the
  current revision remains unresolved until a later successful check covers it.
- `effect-intent` needs `key` and `kind` (`reaction` or `post`). Reactions also
  need `message_ts` and `emoji: "eyes"`; use `key: "eyes:<message_ts>"`.
  Posts use `key: "post:<batch-id>:<full-commit>"`, plus the exact intended text
  and case IDs. Reconcile earlier pending effects before preparing a new batch.
  Keys identify logical effects, not attempts; never choose a new key to retry
  an uncertain action. The helper records intent, not a provider idempotency key.
- `effect-receipt` needs `key`, `outcome` (`done`, `not_sent`, `uncertain`), and
  provider `evidence`. `done` records a confirmed reaction/post identifier or URL;
  `not_sent` requires proof that no action occurred before a retry is allowed.
  Receipts may be reconciled while paused/stopped, without authorizing new writes.
- `pause`, `resume`, `stop` have no other fields. Stop is terminal; pause retains
  evidence and counters. Resume cannot extend the deadline or poll budget.

The ledger enforces identity, budgets, pagination completion, current message
revision, write permissions and uncertain-effect retry guards. The agent owns
truthful input normalization, acceptance quality, batch membership, authorization
interpretation and verification of evidence. Keep Slack content out of public PR
bodies, fixtures and logs. Only sanitized fixtures belong in this skill's tests.
