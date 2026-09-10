# Cost lane diagnosis

Run commands from the skill directory.

## Self-diagnosis

`scripts/pr_cost_doctor.py` classifies every lane. A lane is one harness plus
the reader that turns its transcript into a cost.

```bash
python3 scripts/pr_cost_doctor.py --self-check   # portable, no harness needed
python3 scripts/pr_cost_doctor.py --live         # this machine's newest transcript
python3 scripts/pr_cost_doctor.py                # neither flag means both
python3 scripts/pr_cost_doctor.py --json         # the report as JSON
```

The six statuses:

| status | meaning | exit |
|---|---|---|
| `ok` | the reader ran and satisfied the shared contract | 0 |
| `broken` | the reader ran and violated the contract, or crashed | **1** |
| `no-signal` | the reader returned zero tokens from real input | **1** |
| `unavailable` | the lane exists, but this machine has no transcript to read | 0 |
| `adapter-only` | a hook adapter exists, but no usage reader | 0 |
| `unsupported` | the skill claims no lane for that harness | 0 |

Only `broken` and `no-signal` exit non-zero.

**`unavailable` is not a pass.** It means the doctor could not test the lane at
all. A machine without Codex installed is not a Codex lane that works, and
telling those two apart is the whole reason to run this. Read the per-run
columns (`self-check=` and `live=`), not just the lane status.

`--self-check` is the portable mode. It runs every lane against a synthetic
transcript the doctor generates, so the contract is provable on a machine with
none of these harnesses installed, and in CI. `--live` reads the newest
non-empty transcript under `~/.claude/projects/` or `~/.codex/sessions/` and is
therefore machine-dependent.

`usd_basis` is reported per lane, because the lanes no longer share one basis:

```
usd_basis: claude=default-rates, codex=default-rates, opencode=provider-reported
```

`default-rates` means the reader priced the session at fixed rates and never
used the model name it reports, so a cheap-model session is billed at the
default lane rate. `model-rates` means the model name matched a prefix in the
reader's rate table (claude: sonnet/haiku/opus-4 families; codex: gpt-5,
gpt-4.1, o3/o4-mini, codex-mini), so the estimate uses that model's public
list prices — still list prices, not the account's actual billing. Explicit
CLI rate flags override the table and report `default-rates`. The codex
reader prices `cached_input_tokens` (a subset of `input_tokens`) at the
cache-read rate; the claude reader keeps cache tokens out of `tokens_in` and
prices the read/write split directly.
`provider-reported` means the harness recorded what the provider actually
billed.

Neither value means `measured`. `provider-reported` is a number this repo
copied rather than computed, and nothing here verifies it against an invoice.
Read it as better sourced than an estimate, not as an audited figure.
