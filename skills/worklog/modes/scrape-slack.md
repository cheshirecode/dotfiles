# scrape-slack

Preview Slack-derived task enrichments, then apply only after an explicit
human/agent review. This mode is intentionally workspace-agnostic: it scrapes
whichever Slack workspace(s) the target clone's resolved LDAP/SSO identity can
access. It must not assume an Ideogram Slack tenant.

## Preamble

**Env prerequisite:** this mode still needs `WORKLOG_BIN` + `WORKLOG_REPO` (and usually a resolved LDAP) even when the skill table marks scrape as no AGENTS read. Empty env is a cold-session miss.

Run the target clone environment first:

```bash
direnv exec "$WORKLOG_REPO" "$WORKLOG_BIN/scrape-slack.sh" --format=json "$@"
```

If `WORKLOG_BIN` is unset, use the skill source default:
`$HOME/Documents/oss/dotfiles/skills/worklog/bin`.

## Provider boundary

- **Env/API provider:** if `SLACK_BOT_TOKEN` (or `SLACK_TOKEN`) is set in the
  environment via `.envrc` and no `--input` is given, the helper calls Slack
  `auth.test` to discover the workspace, then `search.messages` for each active
  task slug. Results are shaped into the same fixture format. Rate-limited
  (0.5s between calls). Token is never logged or written to disk. Use
  `--no-env` to disable this provider path even when a token is set.
- **Codex/Claude connector provider:** the agent reads Slack through its Slack
  tool/connector, then passes a captured JSON result set to
  `scrape-slack.sh --input=<file>`. The shell helper cannot call MCP tools by
  itself.
- **Disabled provider:** no Slack auth/input available. Exit 0 with
  `status: unavailable`, no writes.

Every preview must report searched/skipped workspaces and auth limitations.
Unknown or partial coverage is non-mutating.

## Mutation gate

Default behavior is dry-run JSON. Mutation requires `--apply`, which writes
redacted durable summaries plus canonical Slack permalinks under `external_refs`
and appends a human-readable `## Notes from Slack` section. The helper still
emits the full preview in the same JSON output so the caller can audit what was
written.

`--apply` writes **only** to `edit_candidate` proposals — own-namespace, active
(non-archived), non-duplicate, unambiguous, score≥threshold. All other actions
(`proposal_only`, `duplicate_ignored`, `unmatched`) remain non-mutating.

The writer does not commit. The result JSON's `checkpoint_batch` field is the
commit handoff — pipe it to `checkpoint-batch.sh` to commit with proper
`Worklog-Slug:` trailers and a `last_updated` bump:

```bash
scrape-slack.sh --input=results.json --apply | \
  python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['checkpoint_batch']))" | \
  checkpoint-batch.sh
```

Idempotent: re-running `--apply` with the same input is a no-op because the
permalink is already in `external_refs` (matched at the permalink-dedup layer).

Private surfaces require explicit flags:

- `--include-dms`
- `--include-mpims`

Without those flags, skip DM/MPIM fixture entries and report them as skipped.

## Matching policy

Score Slack threads/messages against active tasks by:

1. explicit slug
2. existing Slack permalink
3. Linear / PR token
4. project token
5. title / thread keyword overlap

Only documented-threshold current-owner active-task matches are edit
candidates. Ambiguous/fuzzy matches are proposal-only. Peer-owned tasks are
proposal-only. Archived tasks are never revived. Duplicate permalinks are
ignored.

Never write raw Slack transcripts. Summaries must be redacted and durable:
decision, blocker, context, or follow-up.

## Connector-capture orchestration

End-to-end workflow for an agent with a Slack connector (MCP tool, API, or
browser extension). The shell helper cannot call Slack connectors directly;
the agent bridges that gap by capturing results to JSON, then piping through
the apply → commit pipeline.

**Shortcut:** if `SLACK_BOT_TOKEN` is set in `.envrc`, skip Steps 1–2 and run
`scrape-slack.sh --commit` directly — the env/API provider handles search and
shaping internally. Use the connector-capture path only when you need
thread-level capture beyond what `search.messages` returns.

### Step 1 — capture

Use the agent's Slack connector to read threads/channels relevant to in-flight
tasks. Shape each result into the fixture format:

```json
{
  "workspace": {"id": "T1", "name": "workspace-name"},
  "messages": [
    {
      "permalink": "https://<workspace>.slack.com/archives/<channel>/p<ts>",
      "channel": "C123456",
      "channel_name": "optional-human-name",
      "ts": "1234567890.123456",
      "thread_ts": "1234567890.123456",
      "surface": "public",
      "text": "full message text including any slug / ENG-123 / PR #456 mentions",
      "summary": "one-line durable summary: the decision, blocker, or follow-up"
    }
  ]
}
```

Fields:

- `permalink` — canonical Slack URL. Required for dedup; without it the
  message is unmatched.
- `surface` — `public` (default), `private`, `dm`, or `mpim`. DM/MPIM entries
  are skipped unless `--include-dms` / `--include-mpims` are passed.
- `text` — raw message text. The matcher scans this for slug, Linear, PR, and
  keyword overlap. Secret-shaped tokens (xoxb-, ghp-, sk-, AKIA-, AIza-) are
  redacted before any write.
- `summary` — the durable one-liner that lands in `external_refs.note` and
  `## Notes from Slack`. Should capture the engineering signal (decision,
  blocker, context, follow-up), not transcribe the thread. Max 220 chars.

Write the captured JSON to a temp file (e.g. `/tmp/slack-capture.json`).

### Step 2 — preview (dry-run)

Always preview before applying. This audits match scores, surfaces ambiguous
or peer-owned matches, and verifies no raw secrets leak:

```bash
"$WORKLOG_BIN/scrape-slack.sh" --input=/tmp/slack-capture.json --format=json
```

Review the `proposals` array:
- `edit_candidate` — will be written by `--apply`.
- `proposal_only` — ambiguous, peer-owned, archived, or below threshold.
  The agent can manually enrich these tasks if warranted, but the tool won't.
- `duplicate_ignored` — permalink already in the task file; no-op.
- `unmatched` — no task matched; no-op.

### Step 3 — apply + commit

When the preview looks correct, chain apply → checkpoint-batch in one
pipeline:

```bash
"$WORKLOG_BIN/scrape-slack.sh" --input=/tmp/slack-capture.json --apply --format=json | \
  python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['checkpoint_batch']))" | \
  "$WORKLOG_BIN/checkpoint-batch.sh"
```

This writes `external_refs` entries + `## Notes from Slack` sections to
`edit_candidate` task files, then commits all touched files in one atomic
commit with proper `Worklog-Slug:` trailers and `last_updated` bump.

Idempotent: re-running with the same input is a no-op (permalinks already
recorded → deduped at the matcher layer).

### Agent guardrails

- **Preview before apply.** Never skip Step 2. The preview catches mis-matches,
  ambiguous scores, and redaction failures before they hit task files.
- **Never write raw transcripts.** The tool redacts secret-shaped tokens, but
  the agent should also avoid putting PII or sensitive URLs in the `summary`
  field. Summaries are durable decisions/blockers, not thread transcripts.
- **Respect ownership.** Peer-owned tasks are `proposal_only` — the agent can
  suggest enrichments to the task owner (e.g. via `## Notes from <ldap>`),
  but must not write to peer namespaces directly.
- **Archive is terminal.** Archived tasks are never revived by scrape-slack.
  If an archived task has new Slack context, open a new task with `reopens:`.
- **Clean up temp files.** Remove `/tmp/slack-capture.json` after the pipeline
  completes — it may contain redacted-but-sensitive context.
