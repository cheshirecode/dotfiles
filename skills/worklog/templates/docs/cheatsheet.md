# Cheatsheet — imperative-only

Derived view of `AGENTS.md`. Imperatives only; no rationale. Consult `AGENTS.md` for the *why* and the long-tail; consult this for fast reference.

## Slugs

- `^(eng-\d+-)?[a-z0-9]+(-[a-z0-9]+)*$`. No `wip-`. Linear ID known → `eng-<N>-<desc>`. Else bare `<desc>`.
- Rename: `bin/checkpoint.sh <new> --rename=<old>`. Cross-task references: `bin/refactor.sh <new> --rename=<old>`.

## Status FSM

- Linear: `draft → in-progress → in-review → shipping → archived`.
- Side: `blocked` — `next_action` MUST start with `Waiting on`.
- Flip status with `bin/checkpoint.sh <slug> --status=X`. Never edit frontmatter `status:` by hand alongside a separate `Worklog-Status:` trailer.
- `--status=archived` is rejected by checkpoint — use `bin/archive.sh`.

## Editing rules

- Edit only `people/$LDAP/`. Other namespaces are read-only.
- Never `git rebase`, `git pull --rebase`, or force-push during normal sync.
- Maintenance ops (`bin/log-compact.sh`, `bin/cache-purge.sh`) rewrite history deliberately and emit a recovery prompt via `bin/post-rewrite-prompt.sh`. They are the carve-out.
- Prior-art grep before editing infrastructure surfaces (gsutil, nginx, terraform): `bin/related-search.sh <surface-keyword>`.

## Tooling — what to call

- Save state: `bin/checkpoint.sh <slug>` (single) or `bin/checkpoint-batch.sh < json` (atomic multi-task).
- Archive: `bin/archive.sh <slug> --reason=<shipped|superseded|abandoned|merged|obsolete>`.
- Slugless safety snapshot: `bin/autosave.sh`. Wired to `PreCompact` / `SessionEnd` hooks via `bin/install-hooks.sh --write`.
- Standup: `bin/status.sh [--since=... --project=... --slug=...]`.
- Per-task pack: `bin/context.sh <slug> [--for=resume|review|compact]`.
- New-task plan: `/worklog plan <task>` — structured CoT/ToT/Reflexion block, paste-ready into a task body. Pure generator (no preamble, no writes).
- Find a slug: `bin/slug.sh <fragment>` (exact / substring / Levenshtein).
- Search the corpus: `bin/search.sh <pattern> [--active|--archive] [--kind= --status= --project= --linear= --pr= --repo= --ldap=]`. rg-first body search with frontmatter filters via `.cache/index.jsonl`; supports `--list` (no pattern, slugs only) and `--json`. For code-level lookups invoke the `/serena-rg-search` skill.
- Semantic search: `bin/search.sh <query> --semantic [--top=10] [filters...]`. Cosine over `.cache/index.embeddings.jsonl` (build with `bin/embed.sh`; fastembed + BAAI/bge-small-en-v1.5, 384 dim, local-only). Use for paraphrase queries (e.g. `"lock between concurrent agents"` finds `worklog-task-mutex-isolation`). Filters compose.
- Codex command-menu drift: `bin/codex-surface-check.sh`.
- Multi-task project: `bin/project.sh new|next|claim|release|reap|verify|list <slug>` — see `people/$LDAP/active/worklog-project-mode.md`. `new` takes `--goal --objective` + tasks-JSON on stdin (`[{"slug":"a"},{"slug":"b","depends_on":["a"]}]`); `--dry-run` previews. `next <project>` prints the first claim-eligible child slug (deps satisfied = `status: archived`). `claim <slug>` / `claim next <project>` writes a per-task `claim:` block (advisory mutex; resolved via `$CLAUDE_CODE_SESSION_ID` / `$CODEX_SESSION_ID` / `$CURSOR_SESSION_ID` else per-machine UUID). `release <slug>` clears your own claim. `reap [--session=ID] [--stale=DUR]` clears stale claims (by session or by heartbeat-age). `verify <slug> | --all` reports cycles + parent_slug drift + orphan claims (exit 0/1/2). `list` rolls up project status. `/stacking-strategy` markdown → tasks-JSON via `bin/_stacking_strategy_parser.py`.
- Lint: `bin/lint.sh [--cross-task]`. Composite report: `bin/audit.sh`.
- SQL: `bin/sql.sh new|run|list|show <slug> <name>`. Per-slug queries live at `queries/<slug>/<name>.sql`.

## Frontmatter reference

- Valid `kind` values: `bug` `bugfix` `cleanup` `debug` `design` `impl` `infra` `investigation` `ops` `perf` `plan` `postmortem` `program` `proposal` `review` `runbook` `spike` `tooling`
- Notion page IDs belong in `notion: <id>` (no dashes) — not in `external_refs:`. The `notion:` field is what `init --full` matches against.

## Body conventions

- Cite cross-task references in `related[]` not just body prose.
- Bare body slug references auto-wrap to `[[<slug>]]` via `bin/auto-slug-link.py` (Obsidian backlinks). Frontmatter slugs stay bare (load-bearing per AGENTS.md § Slug as join key).
- Round-trip safe: `grep -l '<slug>' people/` matches both forms.

## Commits

- Trailer `Worklog-Slug:` MUST resolve to an existing task file. Trailer `Worklog-Status:` MUST match frontmatter `status:` for that slug. Both enforced by `bin/git-hooks/commit-msg`.
- Hand-rolling `git commit -m "...Worklog-Status: in-review"` without flipping frontmatter via `--status=` is rejected.

## Hooks

- Pre-commit blocks: lint errors on staged task files, scrubber/round-trip regressions, ruff/shellcheck errors, secret leaks via `bin/pre-commit-scan.sh`.
- Commit-msg blocks: typo `Worklog-Slug:`, trailer-vs-frontmatter status drift.
- Post-commit advisory (TTL 1h): cross-task lint warnings, retro prompt on archive.
- Bypass any hook: `WORKLOG_NO_HOOK=1 git commit ...` (one-shot, last-resort).

## Sessions

- Multi-session collision warning fires on `bin/checkpoint.sh` when another session touched the same slug <5min ago. Advisory; never blocks.
- Resume kernels: `.cache/compact-kernels.{md,json}`. Read the `.json` first; dedupe `TaskList` against existing subjects before `TaskCreate`.
