# Council report

Load at Stage 6, after ballot validation and tally.

## Output format

### Status verdict style

When emitting a status verdict, use telegraphic keyword phrases. Valid status words are `RUN`, `SKIP`, `KEPT`, `REJECTED`, and `UNVERIFIED`.

Examples:

- `RUN multi-angle research justified`
- `SKIP single-agent answer`
- `KEPT support threshold met`
- `REJECTED hard reject veto N-THRESHOLD-MET`
- `UNVERIFIED insufficient valid ballots`

### Live progress log

During execution, short progress notes are fine:

- `Stage 1 research: 3 angles spawned`
- `Stage 4 candidate list: 12 items, 0 invented`
- `Stage 5 voting: 3 of 3 voters returned`

Do not present the live progress log as the final answer.

### Final report

The final report is outcome-first. The first 25 rendered lines should show the decision summary, not ballots. Use the following section headings and table formats verbatim in the output:

## Outcome

| Field | Value |
|---|---|
| Status | `VERIFIED` or `UNVERIFIED: <reason>` |
| Mode | `<foreground|background>` |
| Angles | `<returned>/<planned>` |
| Voters | `<returned>/<planned>` |
| Kept | `<count>` |
| Rejected | `<count>` |

## Kept Items

| Item | Source | Approve | Qualify | Reject | Decision | Reason |
|---|---|---:|---:|---:|---|---|
| 1 | A1-i2, D-i1 | 3 | 0 | 0 | KEPT | support threshold met |

## Rejected Items

| Item | Source | Approve | Qualify | Reject | Decision | Reason |
|---|---|---:|---:|---:|---|---|
| 2 | A2-i4 | 2 | 0 | 1 | REJECTED | hard reject veto SOLVES-EXTANT-PAIN |

## Stage Notes

- Stage 1 research: one-line summary per angle.
- Stage 3 discussion: agreements, disagreements, and gaps.
- Stage 4 collation: `0 items invented; X items deduped`.
- Stage 6 tally: support threshold `ceil(M_returned / 2 + 1)` with odd `M_returned >= 3` and at least 3 valid ballots per kept item.

## Audit Appendix

Put full Stage 5 ballots here, after the outcome and vote tables.
