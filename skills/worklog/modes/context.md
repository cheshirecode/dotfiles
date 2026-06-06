# Mode: `context`

Pure dispatch. Read-only.

```bash
cd "$PROJECTS_DIR/_worklog" && bin/context.sh <slug> "$@"
```

Pass-through flags: `--for=resume|review|compact` (default `resume`), `--format=markdown|json`. Follows `Worklog-Previous-Slug:` through renames; locates the file under `people/$LDAP/{active,archive}/`.

**MANDATORY post-action — hydrate the tracker.** The script's output ends in a `Tracker-ready snippet` block. Emit every `TaskCreate` call in that block **as parallel tool calls in a single tool-use turn** (one assistant message, N concurrent `TaskCreate` blocks). Skip if ≤2 unchecked items remain. Skip items already present (`TaskList` first, dedupe by lowercased subject). Codex: `update_plan`. Cursor: canvas todo card.

Render the script's main output verbatim.
