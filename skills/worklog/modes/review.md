# Mode: `review`

Periodic worklog protocol review across structure / skills / commands / performance. Templates the iteration-loop pattern that produced `worklog-review-2026-04`. Run when something feels off, when the corpus has grown materially, or on a calendar cadence.

**Does not run the preamble. Read-only at first; only writes when creating/updating the review task file at the user's confirmation.**

## When to run

- Quarterly cadence (or whenever pain is observable)
- After a major protocol shift (a new helper landed, a new mode shipped, FSM changed)
- When friction recurs in a single session — that's the strongest signal that a gap exists

Skip if: nothing has changed in `bin/`, `~/.claude/skills/worklog/`, `AGENTS.md`, or `docs/protocol.md` since the last review AND no new friction observed.

### Lightweight delta sub-shape (when running <30 days after the previous review)

If a review fires in the wake of a recent ship batch (i.e. the previous review's Tier 1 just landed and we're checking what surfaced), the full 6-iteration loop is over-ceremony. Use this short shape instead:

1. **Iter 0 — facts captured.** Always do this. Concrete table comparing the last review's numbers vs today's (active/archive counts, commit count, helper latencies, ship list).
2. **Skip iterations with nothing new to report.** If structure / skills / commands haven't materially changed since the previous review, write "Nothing new" + one sentence and move on. Don't pad with restated findings.
3. **Concentrate on what *this* session surfaced.** New friction observed in the session that triggered the review is the load-bearing signal — call it out explicitly per axis.
4. **Iter 6 (synthesis) is still required.** Tier 1 / 2 / 3 ranking grounds the recommendations against the existing backlog. Keep the rejection record honest.
5. **Closing.** Be explicit about the cadence — "this is a delta-since-X review, full quarterly is still due in YYYY-MM."

The lightweight form is for the case where the protocol just shipped a batch and you want to ratify "did the ship land cleanly + what's left." It is NOT a substitute for the quarterly pass; that one still happens against the full 4 axes.

## What it produces

A new task file at `people/$LDAP/active/worklog-review-YYYY-MM.md` with:

- 4 axis sections (structure, skills, commands, performance)
- 1 cross-cutting synthesis section (multi-repo / multi-session friction)
- 1 Karpathy synthesis ranking findings into 3 tiers (build now / backlog / rejected)
- An iteration log of facts captured per axis

The shape is fixed; the content is empirical to whatever's actually painful in the moment of review.

## Iteration loop

1. **Iter 0 — baseline facts.** Capture concrete numbers: commit count, active/archive counts, helper latencies (`time "$WORKLOG_BIN/status.sh"`, `time "$WORKLOG_BIN/lint.sh" --cross-task`, etc.), tasks per repo, today's session evidence.
2. **Iter 1 — structure gaps.** Frontmatter schema, `active/`/`archive/` boundary, relations graph, slug-as-join-key, `.cache/`. Cite concrete observations. Cost + risk per gap.
3. **Iter 2 — skills gaps.** Mode files, init/sync/context/spawn/import/export/lint/review wrappers, mode-doc drift.
4. **Iter 3 — `bin/*` command gaps.** Helper scripts, hook integration, refactor candidates.
5. **Iter 4 — performance gaps.** Profile any helper whose latency feels off. Cite measurements.
6. **Iter 5 — cross-repo / cross-session friction.** Sessions on multiple machines, sibling-repo hooks racing, force-push reconciliation, in-session tracker drift.
7. **Iter 6 — Karpathy synthesis.** Rank into Tier 1 (build now) / Tier 2 (backlog, trigger-based) / Tier 3 (explicitly rejected). Surface tradeoffs honestly.

Each iteration must:
- Cite **concrete evidence** — file path, command output, session episode. No vibes.
- Distinguish **gap** (current state inadequate) from **improvement** (current state OK, here's better).
- State **cost** (small / medium / large) and **risk** (low / medium / high) per item.
- Identify **what's NOT a gap** — Karpathy 2 simplicity-first means rejecting speculative changes by default.

## Out of scope

- Cross-team adoption — frame is single-user-multi-session unless explicitly broadened.
- Compaction / lifecycle / log-tooling work — covered separately by `worklog-log-compaction-squash` + `worklog-log-digest-tool`. This review touches them only at intersection points.

## Outputs (the task body grows section-by-section)

```yaml
slug: worklog-review-YYYY-MM
status: in-progress
kind: review
repos: [_worklog]
project: worklog-automation
next_action: "Loop iterations 1-6 surveying ... ; synthesize ranked recommendations Karpathy-style; checkpoint each iteration."
```

Body sections (filled per iteration):
- `## Survey scope` — fixed list of 4 axes
- `## Iter 0 — facts captured`
- `## Iter 1 — structure gaps` (table: gap / evidence / cost / risk)
- `## Iter 2 — skills gaps` (same shape)
- `## Iter 3 — bin/* command gaps` (same shape)
- `## Iter 4 — performance gaps` (same shape)
- `## Iter 5 — cross-repo / cross-session friction` (same shape)
- `## Iter 6 — Karpathy synthesis + ranked recommendations` (3 tier tables)
- `## Final state` — small table of tier counts and combined effort

## Closing

After Iter 6:
1. Surface the Tier 1 list + ask the user to approve / trim
2. On approval, **shipping each Tier 1 item is a separate commit** to keep changes surgical
3. Tier 2 lives in the task body; reopen via a `## Status update YYYY-MM-DD` section when triggered
4. Tier 3 stays as the rejection record; revisit only with new evidence

The review task itself stays `in-progress` until all approved Tier 1 items ship; then archive with `--reason=shipped --summary="<Tier 1 recommendations shipped>"`.

## Reference

- `worklog-review-2026-04` is the canonical example produced by this mode (1st run)
- `docs/lessons.md` 2026-04 entry on `TaskCreate` drift was a Tier 1 finding from that review
