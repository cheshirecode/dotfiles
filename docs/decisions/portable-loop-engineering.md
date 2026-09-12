# Portable loop engineering

Status: accepted.

## Context

Loop engineering must support resumable work and different agent hosts without
duplicating their schedulers, task queues, or permission systems. Shared code
files and shared Worklog data need explicit ownership even when an agent host
can create isolated code worktrees.

## Decision

Keep the portable skill canonical. The state module owns budgets and terminal
invariants, Worklog owns durable claims/tasks, and evidence-gate owns criterion
coverage. Generate the `loop-run` package from the skill and check for drift.

Use implementer and verifier responsibilities as needed; an architectural review
is warranted when boundaries change. A role can be a sequential pass. Resolve
dispatch and isolation from the actual host capabilities. A role label grants
neither permissions nor filesystem isolation.

Workers return evidence, uncertainty, and a next action. The parent rechecks the
task, repository, and revision/diff identity and serializes shared persistence.
Code-worktree isolation does not isolate Worklog. No-op reviews need evidence,
not artificial commits. Duplicate returns cannot cause duplicate cycle advances.
The operational contracts live in the skill references, not this decision record.

Keep process execution and artifact writes separate from radar interpretation.
Measure change risk using coverage and complexity, then improve missing behavior
and mixed responsibilities. Preserve coherent validation even when its complexity
exceeds a generic threshold. CLI compatibility and rejected-state preservation
are verified at the process boundary.

## Alternatives and consequences

- A plugin may eventually distribute role presets or expose a concrete runtime
  integration. It currently adds a packaging surface without a needed capability.
  If introduced, generate it from canonical skills rather than maintaining another
  policy copy.
- A complete swarm runtime would introduce a daemon, transport, queue, and merge
  topology already owned by other tools. Adopt the useful role/handoff principles
  without that runtime dependency.
- Universal commit requirements exclude read-only reviewers; universal delegation
  requirements exclude hosts without dispatch. Both violate portability.
- Strict typed-evidence parsing would change the existing CLI's non-empty-string
  contract. Typed evidence remains a workflow requirement, with any parser change
  requiring a separate compatibility decision.

The design adapts [swarm-forge's shared rules](https://github.com/unclebob/swarm-forge/tree/f4f5fbcae0de6f7dcc26e82400334227647cfdb2/swarmforge/constitution/articles)
and [role ownership](https://github.com/unclebob/swarm-forge/tree/066a62ffa6cbc8c859262536dc579fecf8535ebb/swarmforge/roles).
Run history, metric snapshots, and implementation checklists belong in Worklog.
