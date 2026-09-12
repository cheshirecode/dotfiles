# Executable examples and acceptance scenarios

Read when state sequencing or verdict handling is unclear. The marked Bash blocks
are executed by `tests/test_documentation.py` in temporary directories. Set
`SKILL_DIR`, `EVIDENCE_GATE` (its script path), and `RUN_ROOT` to existing absolute
paths. For the project-resume example, also set `REPO`, `PROJECT` and the verified
Worklog environment. Tests provide an isolated repo and queue stub; they need no
network, live vault, or model API.

## 1. Verify before completion

<!-- executable: verified-loop -->
```bash
set -eu
run_dir="$RUN_ROOT/verified"
python3 "$SKILL_DIR/scripts/loop_run.py" "$run_dir" --goal "Verify a local artifact" \
  --allowed-effect "write artifacts under $RUN_ROOT" --approval-boundary "writes outside fixture"
printf 'verified\n' > "$RUN_ROOT/result.txt"
python3 "$EVIDENCE_GATE" init --gate "$RUN_ROOT/gate.json" \
  --goal "Verify a local artifact" --criterion 'artifact=Result exists with expected bytes' >/dev/null
python3 -c 'import pathlib,sys; assert pathlib.Path(sys.argv[1]).read_bytes() == b"verified\n"' "$RUN_ROOT/result.txt"
python3 "$EVIDENCE_GATE" record --gate "$RUN_ROOT/gate.json" --criterion artifact \
  --kind artifact --ref "$RUN_ROOT/result.txt" --result 'Expected bytes verified' >/dev/null
python3 "$EVIDENCE_GATE" check --gate "$RUN_ROOT/gate.json" > "$RUN_ROOT/gate-check.json"
verification="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verification"])' "$RUN_ROOT/gate-check.json")"
python3 "$SKILL_DIR/scripts/loop_run.py" "$run_dir" --stop complete \
  --verification "$verification" --evidence "artifact: $RUN_ROOT/result.txt — verified bytes"
```

A failed check must leave the run incomplete. Each goal clause needs its own
evidence; a model's assurance cannot replace the command's result.

## 2. Intervention creates a successor

<!-- executable: bound-successor -->
```bash
set -eu
run_dir="$RUN_ROOT/blocked"
python3 "$SKILL_DIR/scripts/loop_run.py" "$run_dir" --goal "Read restored input" --repo "$REPO" --project "$PROJECT" \
  --allowed-effect "write artifacts under $RUN_ROOT" --approval-boundary "writes outside fixture"
python3 "$SKILL_DIR/scripts/loop_run.py" "$run_dir" --stop blocked \
  --evidence 'artifact: input.txt — missing' --next-action 'Check restored input bytes'
# After authorized intervention; still verify the claimed repair:
printf 'restored\n' > "$RUN_ROOT/input.txt"
successor_dir="$RUN_ROOT/successor"
mkdir "$successor_dir"
# Preserve the verified repo/project configuration for driver probes.
cp "$run_dir/run.json" "$successor_dir/run.json"
python3 "$SKILL_DIR/scripts/loop_state.py" resume --state "$run_dir/loop_state.json" \
  --new-state "$successor_dir/loop_state.json" --evidence 'artifact: input.txt — supplied, pending verification' \
  --next-action 'Check restored input bytes' >/dev/null
python3 -c 'import pathlib,sys; assert pathlib.Path(sys.argv[1]).read_bytes() == b"restored\n"' "$RUN_ROOT/input.txt"
python3 "$SKILL_DIR/scripts/loop_run.py" "$successor_dir" \
  --evidence 'artifact: input.txt — restored bytes verified' --next-action 'Verify goal evidence gate'
```

The predecessor stays blocked and immutable; the successor inherits goal/budget.
A changed goal instead starts a separate linked run. A missing scheduler requires
needs_human; only a verified wakeup supports continue_scheduled.

## 3. Preserve a verdict exit

<!-- executable: verdict-exit -->
```bash
set -eu
# Stub the radar's documented collision verdict, including its exit status.
probe() { printf '{"warn":1,"info":0}\n'; return 2; }
if raw=$(probe); then probe_rc=0; else probe_rc=$?; fi
printf '%s\n' "$raw" > "$RUN_ROOT/verdict.json"
python3 - "$RUN_ROOT/verdict.json" "$probe_rc" <<'PY_VERDICT'
import json, sys
assert int(sys.argv[2]) == 2
assert json.load(open(sys.argv[1]))["warn"] == 1
PY_VERDICT
```

This proves the capture pattern, not a real collision; radar/reap fixtures exercise
the actual tools. Piping a verdict straight into a parser can misclassify the
producer's nonzero result as a parsing error.

For instruction review, also exercise: authorized work with routine unknowns;
shared versus isolated workers; duplicate/stale returns; scoped project delivery;
and Sol orchestrating available Astra/Fable workers. Record actual actions and
capabilities. Review-only scenarios are not execution of another model.
