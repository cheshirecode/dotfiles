# Mode: `sync`

One command handles every save path. Pick the first applicable in order; stop there.

## Non-interactive guard

If `$CLAUDE_HOOK` is set or stdin is not a TTY, skip conversation-WIP detection (it requires judgment). Fall through to autosave only.

## Precedence

1. **Explicit slug.** If the user said `/worklog sync <slug>` (or named a slug in the accompanying message), route to `"$WORKLOG_BIN/checkpoint.sh" <slug>` with any flags they passed (`--status=X`, `--next="..."`, `--pr=N`, `--rename=OLD`). **Archive intent** ("archive", "shipped", "merged", "done", "superseded") → `"$WORKLOG_BIN/archive.sh" <slug> [--pr=N] [--reason="..."] [--summary="..."]` instead.

   On archive: **always generate a 2–3 line `--summary`** before invoking the script. Scan the task body for the outcome, the key invariant, and what's left open; collapse into prose. The script warns if absent but proceeds. The field lands in frontmatter as `summary:` — grep-browsable without opening the file.

   **After the checkpoint or archive succeeds**, hydrate the in-session tracker for the touched slug's still-unchecked `## Next` items (per AGENTS.md § In-session progress visibility): `TaskCreate` for Claude Code, `update_plan` for Codex, canvas todo for Cursor. Skip if there are ≤2 unchecked items remaining (single-step or trivial) or if the slug just got archived (terminal). Use `"$WORKLOG_BIN/context.sh" <slug>` — its "Tracker-ready snippet" section formats each item ready to paste/exec.

   Done.

2. **Conversation WIP with no task file.** Survey:
   - Conversation context: what task(s) is this session mid-way through? Is there a clear slug candidate?
   - Sibling repo (`$PROJECTS_DIR/<repo>` for each repo in scope): `git status`, `git diff --stat`, `gt log` on non-default branches.
   - `gh pr list --author @me --state open` — any PR whose URL doesn't appear in any active task file.

   Classify each finding:
   - `[new]` — no task file; code/diff/PR exists.
   - `[existing]` — tracked; only needs a frontmatter refresh.
   - `[proposal]` — idea in conversation with no code; `kind: proposal`, `status: draft`.

   **Report and wait for confirmation** before writing. Never silently create task files.

   On confirmation:
   - Read `references/protocol.md` from the skill root before creating or hand-editing a task. Do not read it for an existing-slug checkpoint that only invokes a helper.
   - For `[new]`: **prior-art grep first.** Before writing the task body for any new task that locks decisions on a shared surface (GCS paths, nginx config patterns, skill-flow conventions, worklog protocol changes), run `"$WORKLOG_BIN/related-search.sh" <surface-keyword>...` and `"$WORKLOG_BIN/related-search.sh" --projects`. Declare matches in `related[]`; reuse an existing `project:` value if one fits. A 5-second grep here prevents minutes-to-days of unwinding a wrong-by-disagreement decision later. Then write `people/$LDAP/active/<slug>.md` per AGENTS.md template; commit `<slug>: create (backfilled)`. Slug per the grammar in AGENTS.md (`eng-<N>-<desc>` if Linear ID known, else bare `<desc>`; no `wip-` prefix).
   - For `[existing]`: `"$WORKLOG_BIN/checkpoint.sh" <slug> [--status=X] [--next="..."]`.
   - For `[proposal]`: create with `kind: proposal`, `status: draft`, Context opening `Follow-on from <parent-slug>.`; append a `## Notes from cheshirecode` pointer to the parent if active.

3. **Uncommitted `_worklog` edits.** If `git -C $WORKLOG_REPO status --porcelain` is non-empty and the above produced nothing actionable, run `"$WORKLOG_BIN/autosave.sh"`.

4. **Clean.** Report "nothing to sync" and exit.

## Output

Terse. One line per action taken, plus the short SHA pushed.

```
sync:
  checkpoint   eng-1515-stack   (status → in-review)
  backfilled   pillbutton-style-merge  (new)
  autosave     _worklog         snapshot 2026-04-19T14:22:01-0700
pushed at <short-sha>
```

## Lint warnings during sync

`"$WORKLOG_BIN/checkpoint.sh"` runs `"$WORKLOG_BIN/lint.sh" --file=<path>` softly on every save and prints any errors / warnings to stderr (it never blocks the checkpoint; bypass with `WORKLOG_NO_LINT=1`). Treat that output as **advisory**:

- Surface the warnings to the user briefly (don't swallow them) — they often point at FSM drift, missing relations, or YAML shape problems that future tooling will trip on.
- Do **not** retry, revert, or block the sync because of lint output. The commit is already pushed by the time you see it.
- For deeper drift checks (stale review, undeclared body refs), suggest `"$WORKLOG_BIN/lint.sh" --cross-task` — opt-in, slower, intended as a periodic sweep before archive.
