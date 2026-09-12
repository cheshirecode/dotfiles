# Conditional skill context design

## Goal

Reduce the instructions loaded by common routes while preserving decisions,
effect boundaries, commands, and fallback behavior. This builds on the first
prose audit; it does not replace its preserved edits.

The reproducible baseline is published upstream commit
`d871ca2f9a2a3f305b0d37f2caef88c065440dd6`. The final refresh fast-forwarded this
worktree from `804f999`; its only incoming changes were two `pr-cost` tests,
so the instruction baseline and measured counts are unchanged. A separate temporary snapshot of the
first audit measures the incremental effect of this rework; it is not the
published baseline.

## Design

| Skill | Common route | Conditional material | Boundary kept in root |
| --- | --- | --- | --- |
| loop-engineering | start/advance a bounded loop | composition and model/transport choices; mutation preflight; recovery protocol | authorization, serialized writes, typed evidence, stop/gate semantics |
| loop-helpers | build a compact context pack | transport flags, model allowlist, provider caveats | explicit-input pack, no transcript replay, no provider effects |
| which-model | guideline or known-path recommendation | fallback installation resolver | missing-payload refusal and availability gate |

Keep linear council voting and small owner skills intact. Do not introduce
a shared loader or cross-installation filesystem dependency. A root names
the trigger and relative reference; only that reference is read. All-required
routes must also be measured so a smaller root cannot conceal a larger total.

The loop mutation preflight moves verbatim out of the large protocol. Both
entrypoints point to the same owner. A normal write no longer loads unrelated
state recovery, orchestration, and historical verification explanations.
Read each selected file once unless its content changes.

## Checks

1. Measure explicit before/after route file sets, deduplicating files within
   each set. Report UTF-8 bytes, words, and optional `o200k_base` encoded tokens.
   These are offline input-payload counts, not measured billing or cache savings.
2. Move existing assertions with their owner reference. Preserve executable
   resolver, transport, state, budget, and authority tests. Do not retain prose
   in the hot path merely because a test assumed its former location.
3. Verify conditional reads in fresh forward tests, including a mutation route.
   Exercise missing-payload fallback with isolated executable resolver fixtures.
   Check reference content, not just link existence.
4. Run macOS and sibling-sandbox Linux checks against the edited snapshot.
5. Record route tradeoffs and use evidence-gate before completion.

The working tree remains local until publishing is requested. Temporary
baseline copies, encoded measurements, and test logs live outside the repo.

## Measured results

`tiktoken 0.14.0`, `o200k_base`, applied locally to each declared route's joined
file contents. Counts include frontmatter and two newline characters between
files, count a resolved path once, and exclude tool wrappers and conversation
messages. `tests/skill-context-routes.json` makes the file sets explicit.
They are expected route payloads, not automatic read traces or billing data.

| Route | Published baseline tokens | Reworked tokens | Reduction |
| --- | ---: | ---: | ---: |
| loop-observe | 2,918 | 2,239 | +23.27% |
| loop-mutate | 6,757 | 2,713 | +59.85% |
| loop-compose | 2,918 | 2,873 | +1.54% |
| loop-compose-recover-mutate | 6,757 | 6,759 | -0.03% |
| context-pack | 1,034 | 386 | +62.67% |
| context-pack-missing-path | 1,034 | 496 | +52.03% |
| context-pack-and-transport-missing-path | 1,034 | 1,026 | +0.77% |
| model-guideline-known-path | 996 | 829 | +16.77% |
| model-guideline-missing-path | 996 | 1,032 | -3.61% |
| loop-complete | 8,121 | 4,077 | +49.80% |
| model-task-known-path | 4,206 | 4,039 | +3.97% |
| model-catalog-missing-path | 5,068 | 5,103 | -0.69% |

Across all 15 root files, the inventory total falls from **17,783 to 15,406
encoded tokens (13.37%)**. The roots are not all loaded in one normal request.

The common write preflight saves about 60%; a loop route including completion
gate instructions saves about 50%. Context-pack-only requests save about 63%.
The full loop composition/recovery/mutation route is effectively unchanged
(two extra tokens). Model lookup with a missing path costs 3.61% more for the
short guideline route, or 0.69% more when the catalog is also needed. These
fallback tradeoffs are retained to keep the common known-path route smaller.

Compared with the first local prose audit, the additional rework saves roughly
16% on ordinary loop reads and 58% on mutation preflight; composing and loading
all recovery guidance costs roughly 8% and 4% more, respectively. Separating
these comparisons prevents attributing the first pass's edits to this rework.

## Forward checks

Independent evaluators executed the actual helpers with read-only repo access
and private temporary artifacts. Their reported instruction-read sets were:

| Request | Instruction reads | Result |
| --- | --- | --- |
| Build a context pack | loop-helpers root only | schema-version-1 JSON, exit 0 |
| Model guideline, known load path | which-model root only | guideline and availability gate; no resolver/catalog/network |
| Append one line per cycle until three lines, verify, finalize | loop root + effects; evidence-gate root + recording | exact bytes verified; completion gate 2/2; terminal complete |

The first pack evaluator also loaded the loop output section. Removing that
formatting-only dependency made the fresh recheck use only the helper root.
The first mutation evaluator confused `run.json` with state; the root now names
`loop_state.json` explicitly. A fresh recheck completed without the protocol
reference and its marker/gate were independently reread by the lead.

The driver's existing displayed budget counts advances, not the finalization
call: three successful mutation cycles display `complete 2/3`. This behavior
is now explicit; the state engine was not changed as part of a context rework.

The effect preflight content is unchanged; its final blank separator was removed
during the staged whitespace check. The model fallback shell block remains byte-identical and passes five executable cases, including missing,
flattened, shared, legacy, and repo-first installations. Other assertions now
read their owner references and still guard the original semantics.

## Validation and reproduction

- Linux sandbox full suite: **159 pass, 0 fail**.
- Final Linux and macOS static checks: **14 pass, 0 fail** each.
- Final loop Python checks: **106 pass** on each platform.
- Measurement fixtures: **3 pass**, including missing files, duplicate paths,
  Unicode byte counts, and paths containing spaces.
- macOS frozen-copy full suite: **159 pass, 0 fail**.
- After the final `main` refresh, the complete `pr-cost` Python suite passes
  **81 tests on each platform**. Snapshot comparison confirms these two incoming
  test files were the only skill/tool/test differences from the full-suite copies
  before final whitespace cleanup. Three trailing blank lines in new references
  were then removed; a fresh measurement confirmed all token counts unchanged.
- All 12 measurement routes produce identical bytes/words on macOS and Linux.
- Optional `worklog-memory-mcp` e2e remains skipped without package dependencies.

The first macOS run is discarded: editing its live test-runner file during
execution invalidated the shell's read offset. Platform verification now uses
frozen copies. Linux uses the sibling sandbox image with `--user dev`, `--init`,
CI's Ruff 0.15.12, fixture Git identity, and a path containing spaces. No user
credentials or installed skill roots are involved.

From the dotfiles root, reproduce the published-baseline comparison:

```bash
set -o pipefail
baseline=$(mktemp -d)
git archive d871ca2f9a2a3f305b0d37f2caef88c065440dd6 skills | tar -x -C "$baseline"
python3 -m venv "$baseline/venv"
"$baseline/venv/bin/pip" install tiktoken==0.14.0
"$baseline/venv/bin/python" tools/measure-skill-context.py \
  --before "$baseline" --routes tests/skill-context-routes.json --encoding o200k_base
```

Omit `--encoding` to use system Python and report bytes/words without tiktoken.
The tokenizer may download its vocabulary on first use; skill contents are
encoded locally. Full tests: `/bin/bash tests/run.sh all` after loading the
user's Node environment on macOS. Raw logs and snapshots for this run are in
`/tmp/dotfiles-token-rework-a639`; this design and the measurement tool remain
in source so the result does not depend on those temporary files surviving.
