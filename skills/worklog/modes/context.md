# Mode: `context`

Pure dispatch. Read-only.

```bash
(cd "$WORKLOG_REPO" && "$WORKLOG_BIN/context.sh" <slug> --tracker=<active-host> "$@")
```

Pass-through flags: `--for=resume|review|compact` (default `resume`), `--format=markdown|json`, and `--tracker=none|claude|codex|cursor|all`. Select the current host explicitly; use `none` for an unknown host. Direct script calls default to `none`; `all` retains the multi-host compatibility view. Follows `Worklog-Previous-Slug:` through renames; locates the file under `people/$LDAP/{active,archive}/`.

For resume Markdown with at least three open items, verify linked work before hydrating the selected tracker. Drop completed items and deduplicate against the existing tracker. Claude uses the `TaskCreate` argument objects; Codex uses `update_plan` when available; Cursor uses its native tracker. Hydrate only verified surviving items. Compact, review, JSON and `--tracker=none` do not contain a tracker snippet and require no hydration step.

Compact mode skips PR enrichment and emits one evidence commit, at most five current open items, omitted count and a recovery path. Both compact formats carry source content identity and generation/expiry timestamps; JSON is `worklog-context/v1`. Resume Markdown caps the task body at 8000 characters and appends the omitted character count with the task path; read that path for the full text. Resume/review JSON retains its full body and work items. PR enrichment uses `pr_repos`, exact body URLs or one unambiguous task repository; cached task links are not authoritative linkage. Ambiguous/unavailable enrichment is reported explicitly.

Render the script's main output verbatim.

## Reuse and prompt caching

The compact pack is a retrieval index: read the task's accepted decisions and
constraints before dispatch or mutation. An omitted body is not an empty contract.
`content_sha256` identifies the task text; timestamps describe pack generation and
expiry, not when external evidence was verified. Refresh an expired pack and
recheck affected evidence when source, authority or acceptance criteria change.

Keep reusable instructions, tool schemas and shared decisions in a stable order
before task-specific input. Compact projections already put clock fields last;
retain that suffix, including expiry. Do not strip freshness or pad instructions
to pursue cache hits. A matching task hash alone cannot authorize a write or reuse
an old PR verdict. Worklog's derived cache is separate from provider prompt caches.

[OpenAI](https://developers.openai.com/api/docs/guides/prompt-caching) and
[Claude](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
reuse matching prefixes subject to model, settings, boundaries and retention.
Configure breakpoints only through an available, authorized host/API surface;
stable text alone does not prove a cache hit. Preserve host-managed history.
Report provider cache-read/write usage when exposed; otherwise report payload size
and prefix stability as offline checks. Compare total task input/output, retries,
latency and accepted outcomes, not only worker input or cache-hit rate.
