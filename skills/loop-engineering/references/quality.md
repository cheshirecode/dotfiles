# Quality and architecture review

Use the relevant section for regression guards, budgets, requested quality work,
or a concrete boundary risk. [crew.md](crew.md) owns roles and returns.

## Executable constraints

Review existing tests and logic in scope before adding either. Delete duplicate,
implementation-mirroring, obsolete, or speculative checks and branches unless
each protects a distinct observable failure. Prefer a few behavioral regressions
to parameter matrices that repeat the implementation or retest the harness at
several layers.

For each new test, gate, wrapper, configuration, or defensive branch, explain the
concrete failure it prevents, its production/CI consumer, and why coverage is
insufficient. Reuse or extend the smallest maintained check that detects recurrence;
use lint for static
patterns and regression tests for behavior. [The protocol](protocol.md#verifying-a-claim)
owns the failing-case and repair proof. Save replay inputs and control relevant
clock/random sources.

Remove machinery made unnecessary by simplification, including redundant jobs
and handoffs; moving it elsewhere is not removal. Preserve necessary authorization,
isolation, failure propagation, and publication/rollback contracts. Do not weaken
a gate to hide missing coverage or call skipped jobs fast. Preserve required
cache freshness, selected-item isolation, and partial-publication rollback.

Before disabling a test target, inspect imported test ownership and reported case
names: an empty entrypoint can own module tests. Keep a small behavioral check
that missing, skipped, or failing required evidence cannot pass; do not retest the
checker across several layers.

Delete unnecessary work before caching, moving, splitting, or deferring it.
Trace effects through publication: a software/test configuration change does not
justify republishing every item. A selected-item request needs a global scan only
when a real dependency requires it. Scope intentional full rebuilds explicitly.

Declare performance, size, or quality budgets in the definition of done; enforce
them at the appropriate build or runtime boundary.

This adapts [poteto's development notes](https://x.com/poteto/status/2117043478140276847)
to existing project tools and requirements.

## Scope a state-model check

For an ordering or state risk, name one safety property, the states/transitions,
bounds, and environment assumptions. Confirm that a broken variant produces a
counterexample; explain its steps in implementation terms and replay the relevant
implementation behavior. A model pass covers only that model and its assumptions.

This uses the applicable rules from pstack's
[formal-verification skill](https://github.com/cursor/plugins/blob/180939f9e59cc9512e9330649175763e81fad16f/pstack/skills/create-formal-verification-skill/SKILL.md).

## Measure change risk

Start with the project's verification command and the changed behavior. Use its
supported coverage, complexity, duplication, and mutation tools when available;
inspect their help before use. Record the tool version, source revision, measured
scope, and command. A missing tool is unavailable evidence, not a passing score.
Do not require a different language, acceptance framework, or fresh global tool
installation just to follow this reference.
Bound claims to measured scope: synthetic scale, production capacity, server
latency, and client latency are different evidence. Measure the cache/network
layer being claimed; a hit or bypass at one layer does not establish another's
behavior.

CRAP (Change Risk Anti-Pattern) combines cyclomatic complexity and coverage:
`CC² × (1 − coverage)³ + CC`, with coverage expressed as a fraction. State which
coverage measure was used and whether subprocesses were included. Derived scores
from separate tools are estimates; do not label them as another tool's output.
No numeric CRAP score applies to Markdown instructions.

Use high scores to inspect missing behavior and mixed responsibilities. Add tests
for the missing failure paths; preserve rejected-state bytes and terminal
invariants where relevant. Extract a boundary only when it owns a coherent job
and its inputs. Do not split a single decision into helpers accepting already
computed booleans to lower a score. Prefer scoped mutation checks when weak tests
are suspected, and report surviving mutants rather than claiming full coverage
proves the assertions are useful.

## DRY: one owner for each rule

Inspect semantic duplication, not just similar text. Keep state invariants in the
state module, claims in Worklog, and criterion coverage in evidence-gate. IO
adapters translate the owner's answer instead of reimplementing its policy.
Generated package copies must come from their canonical source and pass the
existing drift check. Share instructions by reference where duplicated rules have
diverged; leave unrelated repetition alone.

## Liskov: preserve behavior across substitutions

For host adapters and role specializations, check that substituting one supported
implementation does not strengthen prerequisites or weaken guarantees. A read-only
worker must be able to return useful evidence without committing; a missing
optional dispatch tool must leave authorized in-band execution available. Check
the actual harness capabilities before granting write ownership.

Preserve existing CLI flags, exit codes, schemas, budgets, and terminal meanings
unless a compatibility change is explicitly in scope. Check distinct observable
failures at the real boundary, reusing adequate existing coverage.
Keep testable interpretation separate from process execution, file writes, and
network access; retain integration checks that prove the adapter uses that logic.

These practices adapt [swarm-forge's engineering rules](https://github.com/unclebob/swarm-forge/blob/f4f5fbcae0de6f7dcc26e82400334227647cfdb2/swarmforge/constitution/articles/engineering.prompt)
and [architecture role](https://github.com/unclebob/swarm-forge/blob/066a62ffa6cbc8c859262536dc579fecf8535ebb/swarmforge/roles/architect.prompt)
to the existing portable skill and its ownership boundaries.
