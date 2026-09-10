---
name: pr-review
description: Review one PR or close out completed work. Use for review PR, tighten up PR, wrap up this PR, or pr-review requests. Routes by ownership and separates code review from the retrospective; multi-PR sweeps belong to ship-hygiene.
---

# pr-review

Resolve `<skill-dir>` from this file's load path; helper scripts live in its
`bin/`. Work on the named PR at its verified current head and target.

## Route first

- **Review** (`review PR #N`, `/pr-review N`): read
  [references/review.md](references/review.md). It selects self-check or
  other-review after common preflight.
- **Closeout** (`tighten up PR #N`, `wrap up this PR`): read
  [references/closeout.md](references/closeout.md). It preserves the ordered
  distill → codify → title/body cleanup → checkpoint workflow.

Load only the selected mode. Both require
[references/preflight.md](references/preflight.md) and use the single
[references/title-body.md](references/title-body.md) procedure. A clean PR
needs a short verdict and evidence; do not manufacture findings.

## Boundaries

Ownership errors never grant self-edit permission. Other-review is report-only;
posting requires explicit authorization, including authorization already given
in the conversation. Preserve unrelated working-tree changes when checking out
or testing a PR. Drafts receive structural checks before deeper review.

`ship-hygiene` owns the multi-PR dashboard and delegates individual reviews here;
never call it back from a per-PR operation. This skill owns `bin/leak-scan.sh`.
`tightening-a-pr` remains a compatibility alias; its skill owns the legacy
output mapping. Closeout alone may invoke council and Worklog as routed.

For brittle outputs, invoke `$example-led-instructions`: 0/1/few-shot gate, max 1-3 examples, skip if obvious.
