# Mode: `context`

Pure dispatch. Read-only.

```bash
(cd "$WORKLOG_REPO" && "$WORKLOG_BIN/context.sh" <slug> --tracker=<active-host> "$@")
```

Pass-through flags: `--for=resume|review|compact` (default `resume`), `--format=markdown|json`, and `--tracker=none|claude|codex|cursor|all`. Select the current host explicitly; use `none` for an unknown host. Direct script calls default to `none`; `all` retains the multi-host compatibility view. Follows `Worklog-Previous-Slug:` through renames; locates the file under `people/$LDAP/{active,archive}/`.

For resume Markdown with at least three open items, verify linked work before hydrating the selected tracker. Drop completed items and deduplicate against the existing tracker. Claude uses the `TaskCreate` argument objects; Codex uses `update_plan` when available; Cursor uses its native tracker. Hydrate only verified surviving items. Compact, review, JSON and `--tracker=none` do not contain a tracker snippet and require no hydration step.

Compact mode skips PR enrichment and emits one evidence commit, at most five current open items, omitted count and a recovery path. Compact JSON is `worklog-context/v1`; it also carries source content identity and generation/expiry timestamps. Resume/review JSON retains its full body and work items. PR enrichment uses `pr_repos`, exact body URLs or one unambiguous task repository; cached task links are not authoritative linkage. Ambiguous/unavailable enrichment is reported explicitly.

Render the script's main output verbatim.
