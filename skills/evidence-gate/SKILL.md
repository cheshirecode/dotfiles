---
name: evidence-gate
description: Gate completion claims by mapping every observable goal or acceptance criterion to typed command, artifact, Git, GitHub, or URL evidence. Use before marking a multi-clause task, agent loop, deployment, PR, or verification workflow complete, especially when tests passing does not prove delivery, merge, or user-visible success.
---

# Evidence Gate

Require evidence coverage, not a persuasive completion summary. The script
checks that every declared criterion has at least one typed evidence record; the
agent remains responsible for verifying that each record is truthful and
relevant.

## Declare every goal clause

Resolve `<skill-dir>` as this `SKILL.md` file's directory. Use stable lowercase
criterion IDs and an explicit gate path.

```bash
python3 <skill-dir>/scripts/evidence_gate.py init \
  --gate <gate-file> \
  --goal "<full observable goal>" \
  --criterion "tests=full suite passes" \
  --criterion "merge=PR is merged into main"
```

Do not collapse distinct outcomes into one criterion. Tests, commit, deployment,
PR state, and user-visible behavior are separate when the goal names them.

## Record verified evidence

After checking the source, attach evidence to exactly one criterion:

```bash
python3 <skill-dir>/scripts/evidence_gate.py record \
  --gate <gate-file> \
  --criterion tests \
  --kind command \
  --ref "tests/run.sh all" \
  --result "62 pass, 0 fail"
```

Kinds are `command`, `artifact`, `git`, `github`, and `url`. Never record model
prose as evidence. For GitHub completion, inspect the exact PR head, base,
state, non-empty diff, and merged target before recording it.

## Gate completion

Run `check --gate <gate-file>`. Exit `1` means criteria remain uncovered; do not
claim completion. Exit `0` returns a `verification` value containing the
gate-file path and SHA-256 digest. Pass that value to the parent workflow's
completion record.

The digest proves which coverage artifact was checked, not that an evidence
source was interpreted correctly. Preserve the gate file with the task evidence.
