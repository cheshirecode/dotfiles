# Mode: `context`

Thin wrapper around `bin/context.sh`. Read-only — never writes.

Single-task pack for picking work back up after `/compact`, a new session, or when you're reviewing someone else's work. Emits: frontmatter + recent commits (follows renames) + open PR states + open work-item checkboxes + `next_action` + the task body.

Pass-through flags:

| Flag              | Default    | Meaning                                                                          |
| ----------------- | ---------- | -------------------------------------------------------------------------------- |
| `--for=<shape>`   | `resume`   | `resume` (picking up work), `review` (reviewer-shaped — PR states emphasized), or `compact` (minimal kernel for post-`/compact` resumes; ~7 lines)  |
| `--format=<fmt>`  | `markdown` | `markdown` or `json`                                                             |

Invocation: `cd $PROJECTS_DIR/_worklog && bin/context.sh <slug> <flags>`. The script resolves LDAP, locates the task file under `people/cheshirecode/{active,archive}/`, and follows `Worklog-Previous-Slug:` trailers through renames.

Render the script's output verbatim. If `--format=json`, hand the JSON back without pretty-printing commentary.

**MANDATORY post-action — hydrate the in-session tracker.** Before the user can act on the context output, mirror the "Open work items" into your tracker:

- **Claude Code:** `TaskCreate` for each unchecked `## Next` item. Render the script's "Tracker-ready snippet" section (auto-emitted by `bin/_context.py`) verbatim and execute the calls.
- **OpenAI Codex CLI:** `update_plan` populated from the same items.
- **Cursor:** populate the canvas todo card / Plan Mode entries.

Per AGENTS.md § In-session progress visibility (lines 106–135) and `docs/lessons.md` (top-of-2026-04 entry on `TaskCreate` drift). Skip only if the task has ≤2 unchecked items remaining (single-step / trivial). Don't wait for the user to ask.
