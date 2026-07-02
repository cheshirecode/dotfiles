# scrape-slack

Preview Slack-derived task enrichments, then apply only after an explicit
human/agent review. This mode is intentionally workspace-agnostic: it scrapes
whichever Slack workspace(s) the target clone's resolved LDAP/SSO identity can
access. It must not assume an Ideogram Slack tenant.

## Preamble

Run the target clone environment first:

```bash
direnv exec "$WORKLOG_REPO" "$WORKLOG_BIN/scrape-slack.sh" --format=json "$@"
```

If `WORKLOG_BIN` is unset, use the skill source default:
`$HOME/Documents/oss/dotfiles/skills/worklog/bin`.

## Provider boundary

- **Codex/Claude connector provider:** the agent reads Slack through its Slack
  tool/connector, then passes a captured JSON result set to
  `scrape-slack.sh --input=<file>`. The shell helper cannot call MCP tools by
  itself.
- **Env/API provider:** future path for `.envrc`-supplied Slack auth.
- **Disabled provider:** no Slack auth/input available. Exit 0 with
  `status: unavailable`, no writes.

Every preview must report searched/skipped workspaces and auth limitations.
Unknown or partial coverage is non-mutating.

## Mutation gate

Default behavior is dry-run JSON. Mutation requires `--apply`, but the helper
must still preview first and write only redacted durable summaries plus
canonical Slack permalinks under `external_refs`.

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
