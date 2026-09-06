---
name: pr-cost
description: Collect a typed AI cost payload for a newly created GitHub PR, persist it to a local ledger, and optionally post an idempotent PR comment when live writes are explicitly enabled.
---

# pr-cost

Use this skill from harness-specific hook adapters after a successful `gh pr create`.
It is dry by default: it always prefers the local ledger, and it only writes a
GitHub PR comment when `PR_COST_HOOK_LIVE=1`.

Install and verify: [INSTALL.md](INSTALL.md). Adapters live in `adapters/{cursor,claude,codex}/`.

To comment cost on an already-open PR, follow
[Comment cost on an open PR](#comment-cost-on-an-open-pr) below. To check that
the lanes still work, run the doctor: see [Self-diagnosis](#self-diagnosis).

## Files

- Collector: `scripts/pr_cost_collect.py`
- Usage readers: `scripts/claude_session_usage.py`, `scripts/codex_session_usage.py`
- Doctor: `scripts/pr_cost_doctor.py`
- Tests: `tests/test_pr_cost_collect.py`, `tests/test_pr_cost_doctor.py`,
  `tests/test_usage_key_contract.py`
- Fixtures: `tests/fixtures/`

## Contract

The collector emits one JSON object with this required shape:

```json
{
  "schema_version": "pr-cost/v1",
  "harness": "claude | cursor | codex",
  "confidence": "metered | estimated | unavailable",
  "usd": 1.23,
  "tokens_in": 1200,
  "tokens_out": 3400,
  "model": "claude-sonnet-4-20250514",
  "session_id": "session-123",
  "window_start": "2026-08-20T19:00:00+00:00",
  "window_end": "2026-08-20T19:05:00+00:00",
  "pr_url": "https://github.com/owner/repo/pull/123",
  "generated_at": "2026-08-20T19:05:01+00:00",
  "notes": "optional"
}
```

`usd`, `tokens_in`, `tokens_out`, `model`, `session_id`, `pr_url`, and `notes`
may be `null` when the harness cannot supply them. The keys still remain
present so downstream adapters receive a stable typed contract.

## Privacy rules

- Never copy prompts, responses, file contents, or shell output beyond the PR URL.
- Never store API keys, tokens, auth headers, or repo-local secrets.
- Prefer safe metadata only: harness, model, token counts, session identifier,
  bounded timestamps, PR URL, and a short note about confidence.
- Cursor and Codex adapters should treat unavailable data as `null`, not as a
  reason to scrape unrelated local state.

## Harness guidance

- `cursor`: hook payload can detect `gh pr create`, but it does not expose
  token or USD usage. Default confidence is `unavailable`.
- `claude`: `PostToolUse` can observe `gh pr create`. If an adapter already has
  token or pricing inputs, pass them as CLI flags so the collector can emit an
  `estimated` payload. Otherwise it will fall back to `unavailable`.
- `codex`: there is no native PR creation hook. Use a wrapper that feeds a
  matching hook JSON shape to `from-hook`, or call `emit` / `annotate`
  directly with explicit payload fields.

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

The report always states `usd_basis: default-rates`. Both readers price every
session at fixed default rates and never use the model name they report, so a
cheap-model session is billed at the default lane rate. No figure the doctor
prints is measured.

## Environment

- `PR_COST_LEDGER`: optional ledger override. Defaults to
  `~/.local/share/pr-cost/ledger.jsonl`.
- `PR_COST_HOOK_LIVE=1`: enables live `gh pr comment` writes. Unset keeps the
  collector dry and ledger-only.

## Commands

Validate and print a payload:

```bash
/opt/homebrew/bin/python3 scripts/pr_cost_collect.py emit \
  --harness claude \
  --confidence estimated \
  --usd 1.23 \
  --tokens-in 1200 \
  --tokens-out 3400 \
  --model claude-sonnet-4-20250514 \
  --session-id session-123 \
  --window-start 2026-08-20T19:00:00+00:00 \
  --window-end 2026-08-20T19:05:00+00:00 \
  --pr-url https://github.com/owner/repo/pull/123
```

Append to the ledger and optionally comment on the PR:

```bash
/opt/homebrew/bin/python3 scripts/pr_cost_collect.py annotate \
  --fixture tests/fixtures/emit_valid.json
```

Run from a hook adapter by piping the native hook JSON to stdin:

```bash
printf '%s\n' '{"command":"gh pr create ...","exit_code":0,"stdout":"https://github.com/owner/repo/pull/123"}' \
  | /opt/homebrew/bin/python3 scripts/pr_cost_collect.py from-hook \
      --harness cursor
```

`from-hook` is fail-open by design:

- It ignores `gh pr view`, `gh pr comment`, and unrelated commands.
- It exits `0` on parse failures so the harness never blocks PR creation.
- It skips duplicate annotations when the ledger already contains the same
  `pr_url` and `session_id`.

## Comment cost on an open PR

This is the live-annotate recipe. It replaces the one-off handover note that
used to carry it, which froze one machine's absolute paths, one interpreter and
one PR number into the only copy of the procedure.

Run it from this skill directory. Supply the PR number yourself — nothing here
knows which PR you mean.

```bash
PR=<pr-number>
REPO=<owner/name>        # omit to use the current checkout's default remote
READER=scripts/claude_session_usage.py   # or scripts/codex_session_usage.py
READER_FLAG=--jsonl                      # or --path, for the codex reader
HARNESS=claude                           # or codex

# The doctor already knows where this machine keeps transcripts, and picks the
# newest non-empty one. Confirm its session_id is THIS conversation before you
# annotate: newest is not the same as current.
TRANSCRIPT="$(python3 scripts/pr_cost_doctor.py --live --json \
  | python3 -c 'import json,sys
report = json.load(sys.stdin)
for lane in report["lanes"]:
    if lane["harness"] == sys.argv[1]:
        print(lane.get("live", {}).get("transcript", ""))' "$HARNESS")"

USAGE="$(python3 "$READER" "$READER_FLAG" "$TRANSCRIPT")"
printf '%s\n' "$USAGE"        # eyeball session_id and the token counts first

key() {
  python3 -c 'import json,sys
value = json.load(sys.stdin).get(sys.argv[1])
print(value if value is not None else sys.argv[2])' "$1" "${2-}" <<<"$USAGE"
}

PR_URL="$(gh pr view "$PR" ${REPO:+--repo "$REPO"} --json url -q .url)"

PR_COST_HOOK_LIVE=1 python3 scripts/pr_cost_collect.py annotate \
  --harness "$HARNESS" \
  --confidence estimated \
  --usd "$(key usd_estimated)" \
  --tokens-in "$(key tokens_in)" \
  --tokens-out "$(key tokens_out)" \
  --model "$(key model "$HARNESS")" \
  --session-id "$(key session_id unknown)" \
  --window-start "$(key window_start)" \
  --window-end "$(key window_end)" \
  --pr-url "$PR_URL" \
  --notes "Session usage summed by $READER. Cache read/write included in tokens_in where the harness reports it. USD uses that reader's default rates, not the rate of the model named above."
```

Both readers emit the same eight shared keys, so only `READER`, `READER_FLAG`
and `HARNESS` change between lanes. `--confidence estimated` is the honest
level: the figure comes from default rates, never from metered billing.

`PR_COST_HOOK_LIVE=1` is scoped to that one command on purpose. Exporting it
leaves every later `annotate` in the shell live.

Privacy: do not paste prompts, diffs, or file contents into the PR comment.
The collector already wraps a JSON payload. If annotate reports
`"status": "duplicate"`, stop — the Claude cost is already on the PR.
