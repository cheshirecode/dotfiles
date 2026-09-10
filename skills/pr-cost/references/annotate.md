# Annotate an existing PR

Use only for the named PR with explicit authorization for a live comment.

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
  --notes "Session usage from $READER. USD basis: $(key usd_basis unknown). Token counts retain the reader contract; cached tokens are not added again."
```

All three readers emit the same eight shared keys, so `READER`, `READER_FLAG`
and `HARNESS` are what change between the claude and codex lanes.

The opencode lane needs the two reader lines changed rather than swapped: it
selects a session with `--db` / `--session-id` / `--cwd` instead of a
transcript path, so the `TRANSCRIPT` step above does not apply. The collector
accepts `--harness opencode`, so the annotate command itself is unchanged.

`--confidence estimated` is the honest level for the two lanes above: the
figure comes from estimated list prices (model-specific or fallback rates), never from metered billing.

`PR_COST_HOOK_LIVE=1` is scoped to that one command on purpose. Exporting it
leaves every later `annotate` in the shell live.

Privacy: do not paste prompts, diffs, or file contents into the PR comment.
The collector already wraps a JSON payload. If annotate reports
`"status": "duplicate"`, stop — this session/PR annotation already exists.
