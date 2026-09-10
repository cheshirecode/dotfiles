# REVIEW entry point

Code review. Triggers: "review PR #N", "/pr-review N", "do a pr review".

Read [preflight.md](preflight.md), then select self-check or other-review from ownership.
Both modes inspect [title-body.md](title-body.md); other-review reports its
findings without making corrections.

## Self-check mode (own PR)

Run this fast. Verify your own work without pretending to attack yourself.

**Depth budget:** aim for ≤3 API calls, no test execution, diff-size cap at 500 lines. If required current evidence exceeds the budget, report the incomplete check or deepen only as the task warrants; never substitute stale evidence to meet the budget.

1. Checkout PR branch at HEAD. Re-verify at PR's current head — heads move.
2. Apply [title-body.md](title-body.md) for leak scanning, title accuracy,
   and body coherence. Fix only within the shared authorization rules.
3. Quick CI check: did the latest run pass? If not, verify inherited (abbreviated: just merge-base comparison + control PR on same base).
4. Verdict: **correct**, **correct with N fixable items**, or **blocked**.

Self-check may fix issues in place (edit files, amend PR body).

### Self-check output

```
=== self-check #N ===
Verdict: correct / correct with N items / blocked

Fixed:
  - <item> (<command>)

Flagged:
  - <item> (<evidence>)

What I checked:
  - <commands/runs>
```

## Other-review mode (others' PR)

Attack assumptions. Every finding must be verified. Manufacturing a finding is worse than missing one.

A clean PR gets: "this is correct, here is what I checked." Nothing more.

**Depth budget:** full battery — diff fetch, grep sweeps, stash+test cycle, CI status investigation.

### How to attack

- Find the load-bearing assumption — the one fact that, if false, makes the change wrong. Attack that first. Not style.
- For fixes: what invariant does this restore? What else writes to that invariant?
- For boundaries: do both sides agree (reader/writer, config/query)?
- For new tests: check whether the test **actually fails without the change**. Stash the patch, run test, restore. A passing test either way protects nothing.
- For constants/enums/config keys: check reachability. Unreachable branches hide silent misclassification later.
- Ask: second call, empty input, retry. Construct the interleaving that breaks concurrency/cache/ordering changes.
- Prefer one proven finding over five arguable ones.

### Scope discipline

- Review what the diff changes. Do not redesign the feature.
- A latent trap that the diff makes possible IS in scope. Say what would have to change for it to bite.
- Note adjacent problems as follow-ups. Do not fold them into this review.
- If the PR text claims something the diff contradicts — "not in this diff", "no production impact" — that is a finding. Often high-value, because reviewers rely on that text.

### Voice rules

Write simple technical English:

- Short sentences, ~20 words. One idea per sentence. Active voice.
- Plain facts. No idioms, no metaphor, praise padding, throat-clearing.
- Explain as if to someone new. Assume no context.
- Keep exact commands, paths, identifiers, error text unchanged.
- Cite `file:line` for every claim. Quote the line when short.
- State the consequence in user/operator terms, not just mechanism.
- No "great work", no "just", no "simply".
- Never summarize what the PR does.

Structure each finding: claim → evidence → consequence → smallest fix. Order matters.

### Output before posting

1. Re-verify every anchor at the PR's current head. Heads move.
2. Re-read each finding and strike any sentence you did not verify.
3. Drop findings that turned out wrong. Do not soften them into vague concerns.
4. **Require explicit authorization before posting anything; existing authorization counts.** Inline comments only unless asked otherwise. Never post a summary comment by default. Never reply to a human reviewer as if you were the repo owner.

### Other-review output (to human, not posted to PR)

```
=== other-review #N ===
Verdict: correct / correct with findings / blocked

What I checked:
  - <commands/runs>

Findings:
  [HIGH] Claim — verified/unverified/could not determine
    Evidence: <command output + file:line reference>
    Consequence: <user/operator impact>
    Fix: <smallest correction>

  [MEDIUM] ...

Considered but dropped:
  - <finding>: <reason — e.g., "already fixed in commit X", "belongs to parent PR Y">
```
