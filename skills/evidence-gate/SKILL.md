---
name: evidence-gate
description: Gate completion claims by mapping every observable goal or acceptance criterion to typed command, artifact, Git, GitHub, or URL evidence. Use before marking a multi-clause task, agent loop, deployment, PR, or verification workflow complete, especially when tests passing does not prove delivery, merge, or user-visible success.
---

# evidence-gate

Require evidence coverage, not a persuasive completion summary. The script
checks that every declared criterion has at least one typed evidence record; the
agent remains responsible for verifying that each record is truthful and
relevant.

## When to use

- Before marking a multi-clause task, agent loop, deployment, PR, or verification workflow complete
- When tests passing does not prove delivery, merge, or user-visible success
- When you need to map every observable goal or acceptance criterion to typed evidence

Skip if: the task has a single observable outcome with one sufficient check (tests alone prove completion).

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. In most
agent contexts, this is the path from which the skill was loaded. If uncertain,
search for `evidence_gate.py` under the skill root:

```bash
SKILL_DIR="$(dirname "$(find ~/.claude/skills -name evidence_gate.py -print -quit 2>/dev/null)")/.."
# Or, if the skill is in the current repo:
SKILL_DIR="./skills/evidence-gate"
```

All script invocations below use `python3 <skill-dir>/scripts/evidence_gate.py`.

## Declare every goal clause

Initialize with `python3 <skill-dir>/scripts/evidence_gate.py init`; see
[references/recording.md](references/recording.md) for clause wording rules.
## Record verified evidence

**Evidence kinds:** `command`, `artifact`, `git`, `github`, `url`. Never
record model prose as evidence.

See [references/recording.md](references/recording.md) for the record
subcommand, evidence kinds, and worked examples.
## Gate completion

See [references/recording.md](references/recording.md) for the check
subcommand, its exit codes, and the pass/fail contract.
## Inspect the gate

Run `python3 <skill-dir>/scripts/evidence_gate.py show --gate <gate-file>` to
print the full gate JSON (all criteria and their evidence records). Useful for
debugging or reviewing what has been recorded.

## Digest semantics

The SHA-256 digest proves which coverage artifact was checked, not that an
evidence source was interpreted correctly. Preserve the gate file with the task
evidence. If the gate file is modified after `check`, the digest no longer
matches; re-run `check` to regenerate it.
