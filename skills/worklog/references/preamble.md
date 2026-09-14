## Environment bootstrap contract

Run helpers from a shell that has the target clone's environment loaded. Prefer `direnv exec "$WORKLOG_REPO" ...` when the clone has `.envrc`; direct `source` is only safe for plain shell exports and may fail on direnv helpers such as `source_up`. Required shape:

- `WORKLOG_REPO` points at the live data repo (`.../_worklog`). **Required for all modes except `help`.** If unset and the mode is not `help`, error with: `WORKLOG_REPO not set — run from a worklog clone or set it explicitly.`
- `WORKLOG_BIN` points at this skill's `bin/` directory; if unset, use `$HOME/.claude/skills/worklog/bin`.
- `WORKLOG_LDAP` is optional but authoritative when set; otherwise helpers fall back to git email, then `$USER`.
- `--help` paths must not require any of those variables to be set.

**Error handling:** if a helper script exits non-zero, report the error verbatim and stop. Do not retry or work around script failures — the user needs to see the actual failure mode. Exception: `lint.sh` warnings during `sync` are advisory (see `modes/sync.md`).

## Preamble — single call

```bash
cd "$WORKLOG_REPO" && "$WORKLOG_BIN/preamble.sh" [--minimal|--full]
```

Emits `LDAP=`, `PROJECTS_DIR=`, `NAMESPACE=`, `PULL=` key/value lines plus a `### roster` block (top 15 active tasks by `last_updated`, one tab-separated line each). Both paths resolve LDAP and inspect the namespace/roster. Full mode additionally handles the rate-limited pull and dirty-tree autosave.

Skip re-invocation within the same session — preamble.sh is idempotent but the tool turns aren't free.

### Tracker hydration (after preamble)

If the roster is sufficient, skip hydration. For a selected task, follow
`modes/context.md`: request `context.sh <slug> --for=resume --tracker=<active-host>`,
verify open items, and deduplicate before updating that host's available tracker.
Use `--tracker=none` when no tracker is available. Do not load the full kernel
cache for one task or assume every context format includes tracker instructions.

### AGENTS.md / protocol reference / lessons.md

- `$WORKLOG_REPO/AGENTS.md`: read only when the mode table says yes, OR when `references/protocol.md` does not answer a specific edge case. Per-clone — each clone has its own copy seeded from `$WORKLOG_BIN/../templates/AGENTS.md`.
- `references/protocol.md`: read only when the mode table says yes. It is the compact task-writing and helper reference formerly embedded here.
- `$WORKLOG_BIN/../templates/docs/cheatsheet.md`: open only for the long-tail (semantic search filter syntax, project subcommand flags, SQL helper details).
- `$WORKLOG_BIN/../templates/docs/lessons.md`: high-recurrence lessons live in Claude memory (`feedback_lessons.md`) — no read needed for non-review modes.
