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

**Evidence of a change is not evidence of its health.** A verified diff says
nothing about whether the change works. Any clause asserting readiness or a
successful rollout needs separate typed health evidence — see
[references/health-evidence.md](references/health-evidence.md).

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
