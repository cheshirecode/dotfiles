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
usd_basis: claude=default-rates, codex=model-rates, opencode=provider-reported
```

`default-rates` means the reader priced the session at fixed rates and never
used the model name it reports, so a cheap-model session is billed at the
default lane rate. `model-rates` means the model name matched a prefix in the
reader's rate table (claude: sonnet/haiku/opus-4 families; codex: gpt-5,
gpt-4.1, o3/o4-mini, codex-mini), so the estimate uses that model's public
list prices — still list prices, not the account's actual billing. Explicit
CLI rate flags override the table and report `default-rates`.

`unavailable` means no lane rate could be resolved at all, and the lane's
`usd_estimated` and `usd_basis` are both null. The codex reader matches only
an exact known model name or a dated snapshot of one, so a model absent from
the table prices nothing rather than borrowing a same-family rate.

Both readers treat input as three disjoint classes. The codex reader takes
`cached_input_tokens` and `cache_write_input_tokens` as subsets of
`input_tokens` and subtracts both, pricing the remainder at the input rate,
the reads at the cache-read rate and the writes at the cache-write rate. The
claude reader keeps cache tokens out of `tokens_in` and prices the read/write
split directly. Cache writes cost a premium, not the input rate and not
nothing, so a reader that folds them into ordinary input understates the bill.

`provider-reported` means the harness recorded what the provider actually
billed.

None of these values means `measured`. `provider-reported` is a number this repo
copied rather than computed, and nothing here verifies it against an invoice.
Read it as better sourced than an estimate, not as an audited figure.

## Overriding the rates

Both session readers take the same four flags, in USD per million tokens:

```
--input-usd-per-mtok        ordinary (uncached) input
--output-usd-per-mtok       output
--cache-read-usd-per-mtok   cache reads
--cache-write-usd-per-mtok  cache writes
```

Pass them to price a model the table does not know, or to price one at your
account's rates instead of list prices. Passing any of them sets `usd_basis`
to `default-rates`.

Cache writes need their own flag because they are billed at a premium over
input, not at the input rate. Anthropic's published multipliers are 1.25x
input for the 5-minute TTL and 2x for the 1-hour TTL, against 0.1x for reads;
`claude_session_usage.py` encodes those and splits writes by TTL.

Partial rates fill in from the table only when the model matches an exact
known row. For an unknown model, a partial set leaves the cost null rather
than mixing your flag with a guessed rate — supply all the rates the
transcript needs, or accept no figure. Non-finite or negative rates exit 2.
