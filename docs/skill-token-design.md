# Conditional skill context design

## Purpose and boundaries

Keep common skill requests small by loading substantial conditional guidance
only when its trigger applies. The root retains authorization, evidence and
completion requirements. Models and hosts use the same portable file layout;
Astra, Sol, Fable, crew and orchestrator routes remain directly discoverable.

Each rule has one owner. Composition and mutation rules move verbatim from
current loop-engineering into dedicated references. Context packing does not
load transport guidance, and known-path model requests do not load resolver
fallbacks. Independent installations keep their executable resolver fallbacks.
Linear council voting stays together; its quorum, deadlines and voting rules
remain in the root. Short prose edits preserve operational boundaries.

There is no new runtime loader, plugin, provider call or global configuration.
The state engine, timeout fixes and generated package sources are unchanged.
`loop_state.json` is identified explicitly as state; `run.json` is configuration.

## Measurement contract

`tools/measure-skill-context.py` compares declared route file sets in
`tests/skill-context-routes.json`. Each resolved path is read once; contents are
joined with two newlines. Counts include frontmatter. Missing files and malformed
route specifications fail without reporting savings. Bytes and words work with
system Python; encoded tokens require an explicitly selected tiktoken encoding.

These are offline instruction-payload counts, not observed agent read traces,
provider billing, cache savings, latency or actual model context consumption.
The encoding is a reproducible comparison instrument, not a tokenizer claim for
Astra, Sol or Fable. Routes requiring every reference are measured alongside
common routes so deferred content cannot hide a larger complete payload.

The baseline is main at `b3ce50b9cce13abcd642228b4398632a2a6983ad`.
Counts below use tiktoken 0.14.0 and `o200k_base`. Positive reduction means less
input; negative reduction means an increase.

| Route | Baseline tokens | Current tokens | Reduction |
| --- | ---: | ---: | ---: |
| loop-observe | 1,328 | 1,061 | +20.11% |
| loop-mutate | 2,623 | 1,249 | +52.38% |
| loop-compose | 1,328 | 1,395 | -5.05% |
| loop-compose-recover-mutate | 3,232 | 3,332 | -3.09% |
| context-pack | 1,062 | 386 | +63.65% |
| context-pack-missing-path | 1,062 | 496 | +53.30% |
| context-pack-and-transport-missing-path | 1,062 | 1,058 | +0.38% |
| model-guideline-known-path | 996 | 829 | +16.77% |
| model-guideline-missing-path | 996 | 1,032 | -3.61% |
| loop-complete | 2,693 | 2,426 | +9.91% |
| model-task-known-path | 4,338 | 4,171 | +3.85% |
| model-catalog-missing-path | 5,200 | 5,235 | -0.67% |

Common mutation and context-pack routes save the most. Composition adds a small
routing cost when selected; the complete recovery route is about 3% larger.
Missing-path model lookups also cost slightly more. These are explicit tradeoffs
for smaller common routes, with the fallback behavior preserved.

Completion measures the ordinary already-selected evidence gate. It does not
assume a full protocol or mutation-reference read on either side. Recovery routes
include durable-context guidance on both sides. The manifest describes these
assumptions and can be extended for another workload.

## Reproduction and acceptance

From the repository root:

```bash
set -o pipefail
baseline=$(mktemp -d)
git archive b3ce50b9cce13abcd642228b4398632a2a6983ad skills | tar -x -C "$baseline"
python3 tools/measure-skill-context.py \
  --before "$baseline" --routes tests/skill-context-routes.json
```

For encoded counts, create a temporary virtual environment, install
`tiktoken==0.14.0`, and run the same command with `--encoding o200k_base`.
The tokenizer may download its vocabulary on first use; skill contents are
encoded locally.

Acceptance checks cover route file resolution, canonical-rule preservation,
Unicode bytes, duplicate resolved paths, missing files and malformed route data.
Existing executable resolver, context-pack, transport, loop-state and documentation
checks must still pass. Run `/bin/bash tests/run.sh all` with the user's Node
environment. Cross-platform checks use a frozen source copy in the sibling
sandbox's Linux ARM64 image and a path containing spaces, without host credentials.
Detailed execution evidence belongs in the PR or task record, not this design.
