# loop-run

A bounded, evidence-driven loop state machine for agents — the guardrails
that `max_turns` does not give you.

## Why not just max-turns?

Every serious agent SDK caps iterations. That cap answers one question —
"how many times?" — and none of the ones that actually burn money and trust.
This table is the product; every row maps to a test in `tests/`:

| Failure mode | `max_turns` | `loop-run` | test |
|---|---|---|---|
| Loop declares success without proof | allowed | `--stop complete` **requires** `--verification`; refused otherwise | `test_stop_complete_requires_verification` |
| `blocked` / `budget_exhausted` quietly reported as done | allowed | terminal statuses are typed; a non-complete status can never become `complete` | `test_stop_is_terminal_for_every_status` |
| Progress claims are prose | always | every cycle records one **typed evidence line** (`command\|artifact\|git\|github\|url: ref — result`) | `test_advance_requires_evidence` |
| Budget only counts turns | yes | budget carries a unit (`turns`, or your own) and a ceiling; exhaustion is a distinct terminal state | `test_advance_exhausts_budget_without_claiming_complete` |
| Killed loop loses its place | yes | state is a JSON artifact; `resume` creates a **bound successor** — the predecessor stays terminal, auditable | `test_resume_creates_bound_successor_without_reopening_blocker` |
| Two agents edit one repo mid-loop | invisible | optional crew-radar (bundled, bash+git only) folds a conflict verdict into every cycle line | `test_radar_runs_with_repo` |

The $47k/11-day runaway loop incident (2026) happened *with* iteration caps
available. Caps bound the loop; they don't make it honest.

## Use

```bash
pip install loop-run

# one call per cycle — the driver owns state, you own the decision
loop-run ./run --goal "tests pass and PR merged" --budget 20
loop-run ./run --evidence "command: pytest -q — 34 passed"
loop-run ./run --stop complete --verification "ci run 812 green"
```

Each call prints one line:

```
running 3/20 turns — next: <action> | radar: clean | queue: off | decide: continue or stop
```

Exit codes: `0` ok, `2` malformed usage (a `--stop complete` without
`--verification` is caught here, before any state changes), `3` the state
contract refused the transition — a false `complete` is an error, not a
log line.

State corrections are append-only (`fingerprint` + `annotate`); terminal
states never reopen.

## Provenance

Extracted from the `loop-engineering` skill in
[cheshirecode/dotfiles](https://github.com/cheshirecode/dotfiles), where this
state machine has driven real multi-day agent workloads. The vendored
modules are unmodified except for package-relative paths; the 46-test code
suite ships with the package.
