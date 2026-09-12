# Quality and architecture review

Use on requested code-quality work or when changed behavior exposes a concrete
testing or boundary risk. Keep normal one-shot work lightweight. Role ownership
and verification returns live in [crew.md](crew.md).

## Measure change risk

Start with the project's verification command and the changed behavior. Use its
supported coverage, complexity, duplication, and mutation tools when available;
inspect their help before use. Record the tool version, source revision, measured
scope, and command. A missing tool is unavailable evidence, not a passing score.
Do not require a different language, acceptance framework, or fresh global tool
installation just to follow this reference.

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
unless a compatibility change is explicitly in scope. Test success, malformed
input, inconsistent results, and unavailable dependencies at the real boundary.
Keep testable interpretation separate from process execution, file writes, and
network access; retain integration checks that prove the adapter uses that logic.

These practices adapt [swarm-forge's engineering rules](https://github.com/unclebob/swarm-forge/blob/f4f5fbcae0de6f7dcc26e82400334227647cfdb2/swarmforge/constitution/articles/engineering.prompt)
and [architecture role](https://github.com/unclebob/swarm-forge/blob/066a62ffa6cbc8c859262536dc579fecf8535ebb/swarmforge/roles/architect.prompt)
to the existing portable skill and its ownership boundaries.
