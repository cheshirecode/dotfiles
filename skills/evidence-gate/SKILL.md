---
name: evidence-gate
description: Gate completion claims by mapping every observable goal or acceptance criterion to typed command, artifact, Git, GitHub, or URL evidence. Use before marking a multi-clause task, agent loop, deployment, PR, or verification workflow complete, especially when tests passing does not prove delivery, merge, or user-visible success.
---

# evidence-gate

Require evidence coverage, not a persuasive completion summary. The script
checks that every declared criterion has at least one typed evidence record; the
agent remains responsible for verifying that each record is truthful and
relevant.

Skip when one observable outcome has one sufficient check.

## Resolve the skill directory

Resolve `<skill-dir>` to the directory containing this `SKILL.md`. In most
agent contexts, this is the path from which the skill was loaded. If uncertain,
search for `evidence_gate.py` under the skill root.
`loop-engineering/references/resolvers.md` owns this resolver pattern, including the per-host variants and the fixture that executes them; the line below is the same pattern with this skill's own sentinel file.

```bash
# Roots checked in order; empty when absent — never a bogus "./..":
SKILL_DIR="$(for r in ~/.claude/skills ~/.agents/skills ~/.cursor/skills ./skills; do f=$(find -L "$r" -name evidence_gate.py -print -quit 2>/dev/null); [ -n "$f" ] && { dirname "$(dirname "$f")"; break; }; done)"
```

All script invocations below use `python3 <skill-dir>/scripts/evidence_gate.py`.

## Record and check coverage

Read [references/recording.md](references/recording.md) when declaring criteria,
recording evidence, or checking completion; it owns the CLI examples and exit codes.
Start with `python3 <skill-dir>/scripts/evidence_gate.py init`.

**Evidence kinds:** `command`, `artifact`, `git`, `github`, `url`. Never
record model prose as evidence. Evidence of a change is not evidence of its
health — see [references/health-evidence.md](references/health-evidence.md).

## Inspect the gate

Run `python3 <skill-dir>/scripts/evidence_gate.py show --gate <gate-file>` to
print the full gate JSON (all criteria and their evidence records). Useful for
debugging or reviewing what has been recorded.

## Digest semantics

The SHA-256 digest proves which coverage artifact was checked, not that an
evidence source was interpreted correctly. Preserve the gate file with the task
evidence. If the gate file is modified after `check`, the digest no longer
matches; re-run `check` to regenerate it.
