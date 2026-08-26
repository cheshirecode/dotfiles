---
name: evidence-gate
description: Gate completion claims by mapping every observable goal or acceptance criterion to typed command, artifact, Git, GitHub, or URL evidence. Use before marking a multi-clause task, agent loop, deployment, PR, or verification workflow complete, especially when tests passing does not prove delivery, merge, or user-visible success.
---

# evidence-gate

Require evidence coverage, not a persuasive completion summary. The script
checks that every declared criterion has at least one typed evidence record; the
agent remains responsible for verifying that each record is truthful and
relevant.

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

Use stable lowercase criterion IDs (matching `^[a-z][a-z0-9_-]*$`) and an
explicit gate path. Store gate files alongside task evidence (e.g.,
`_worklog/evidence/<task-slug>.json`).

```bash
python3 <skill-dir>/scripts/evidence_gate.py init \
  --gate <gate-file> \
  --goal "<full observable goal>" \
  --criterion "tests=full suite passes" \
  --criterion "merge=PR is merged into main"
```

Do not collapse distinct outcomes into one criterion. Tests, commit, deployment,
PR state, and user-visible behavior are separate when the goal names them.

**Overwrite protection:** `init` refuses to overwrite an existing gate file.
Pass `--force` to replace it (use sparingly; prefer appending evidence).

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

**Evidence kinds:** `command`, `artifact`, `git`, `github`, `url`. Never record
model prose as evidence. Each criterion may have multiple evidence records
(append-only; no edit/remove).

**GitHub example:** For PR merge, inspect the exact PR head SHA, base branch,
state, non-empty diff, and merged target before recording:

```bash
python3 <skill-dir>/scripts/evidence_gate.py record \
  --gate <gate-file> \
  --criterion merge \
  --kind github \
  --ref "https://github.com/org/repo/pull/42" \
  --result "merged commit abc1234 into main"
```

## Gate completion

Run `python3 <skill-dir>/scripts/evidence_gate.py check --gate <gate-file>`.

**Exit codes:**
- `0` — all criteria covered. Prints JSON with `verification` field in format
  `evidence-gate:<absolute-path>#sha256=<digest>`. Pass this value to the
  parent workflow's completion record.
- `1` — one or more criteria uncovered. Prints JSON with `missing` array.
  **Do not claim completion.** Address each missing criterion before re-checking.
- `2` — contract violation (invalid gate file, unknown criterion, etc.).
  Check stderr for the error message.

**Example output (satisfied):**
```json
{
  "covered": ["tests", "merge"],
  "goal": "change is verified and merged",
  "missing": [],
  "status": "satisfied",
  "verification": "evidence-gate:/path/to/gate.json#sha256=abc123..."
}
```

**Example output (unsatisfied):**
```json
{
  "covered": ["tests"],
  "goal": "change is verified and merged",
  "missing": ["merge"],
  "status": "unsatisfied",
  "verification": ""
}
```

## Inspect the gate

Run `python3 <skill-dir>/scripts/evidence_gate.py show --gate <gate-file>` to
print the full gate JSON (all criteria and their evidence records). Useful for
debugging or reviewing what has been recorded.

## Digest semantics

The SHA-256 digest proves which coverage artifact was checked, not that an
evidence source was interpreted correctly. Preserve the gate file with the task
evidence. If the gate file is modified after `check`, the digest no longer
matches; re-run `check` to regenerate it.
