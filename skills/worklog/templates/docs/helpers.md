# Helpers — `bin/*`

Each script self-documents via `--help`. This doc is the composition playbook.
Scripts are shipped by the dotfiles skill. In this doc, `bin/foo.sh` is shorthand for `"$WORKLOG_BIN/foo.sh"`; live data repos normally carry only a `bin/README.md` tombstone.

## When to use which

| Want to…                                         | Use                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------- |
| Update one task (status / next / PR / rename)    | `bin/checkpoint.sh <slug> [--status=X --next="..." --pr=N --include=PATH]` |
| Atomic multi-task checkpoint (one push for N flips) | `bin/checkpoint-batch.sh < json` (reads `[{slug,status?,next?,...}]` from stdin) |
| Archive a shipped/superseded task                | `bin/archive.sh <slug> [--pr=N --reason="..."]`                     |
| Closest-match slug lookup (typo / fuzzy)         | `bin/slug.sh [--all] <fragment>` (exact → substring → Levenshtein)  |
| Multi-task projects with per-task mutex          | `bin/project.sh new\|next\|claim\|release\|reap\|verify\|list` (see `~/.claude/skills/worklog/modes/project.md`) |
| Search task corpus (rg-first + frontmatter filters) | `bin/search.sh <pattern> [--active --archive --kind= --status= --project= --linear= --pr= --repo= --ldap=] [--list] [--json]` |
| Semantic search over corpus (cosine over embeddings) | `bin/search.sh <query> --semantic [--top=10] [filters...]` (build embeddings first with `bin/embed.sh`) |
| Build / refresh the embeddings cache              | `bin/embed.sh [--refresh] [--all]` (writes `.cache/index.embeddings.jsonl`; fastembed + BAAI/bge-small-en-v1.5, local-only) |
| Snapshot the current Claude session into a task's transcript | `bin/transcript-dump.sh <slug>` (writes `people/<ldap>/transcripts/<slug>.md`; watermarked append; auto-fires from `bin/archive.sh` and from `bin/checkpoint.sh --status=in-review\|shipping`; bypass via `WORKLOG_NO_TRANSCRIPT=1`) |
| Safety snapshot of uncommitted worklog edits     | `bin/autosave.sh` (default: `people/$LDAP/`; `WORKLOG_AUTOSAVE_WIDE=1` for full tree) |
| Push debounced autosave commits                  | `bin/autosave-flush.sh` (SessionEnd hook; also after checkpoint/archive) |
| Standup-shaped summary across tasks              | `bin/status.sh [--since=... --project=... --author=...]`            |
| Single-task chronological history                | `bin/status.sh --slug=<slug>`                                       |
| Context pack for one task (resume / review)      | `bin/context.sh <slug> [--for=resume|review]`                       |
| Exact Linear / Notion / PR scan seeds for init   | `bin/init-scan.sh [--ldap=<ldap> --format=json]`                    |
| Preview Slack-derived task enrichments           | `bin/scrape-slack.sh [--input=slack-results.json --format=json]`    |
| Check Codex command-menu drift                   | `bin/codex-surface-check.sh`                                        |
| Validate every task file's frontmatter           | `bin/lint.sh [--format=json]`                                       |
| Guard split clones from foreign-domain content   | `bin/boundary-lint.sh [--format=json]`                              |
| Guard task-scoped writes from foreign dirty task files | `bin/task-guard.sh --slug=<slug> [--format=json]`             |
| Rebuild the derived cross-reference index        | `bin/index.sh` (writes `.cache/index.jsonl`)                        |
| Find children / cross-refs of a task             | `bin/children.sh <slug> [--include-refs]`                           |
| Find tasks referencing a PR number               | `bin/pr.sh <N>`                                                     |
| Find active tasks gone stale                     | `bin/stale.sh [--days=14] [--ldap=X] [--status=X]`                  |
| Composite health report (stale + blocked + drift) | `bin/audit.sh [--ldap=X] [--section=stale|blocked|in-review|drift|boundary|surface]` |
| Cross-task slug rename (also rewrites references) | `bin/refactor.sh <new-slug> --rename=<old-slug> [--apply]`          |
| Wire Claude Code PreCompact hook → autosave      | `bin/install-hooks.sh [--write] [--uninstall]`                      |
| Compact same-slug checkpoint bursts in `git log` | `bin/log-compact.sh [--slug=X --since=DATE --apply]` (single-committer only; rewrites history; tags `pre-compact-<ts>` for safety) |
| Remove `.cache/`-prefixed paths from history (one-shot) | `bin/cache-purge.sh [--apply]` (single-committer only; rewrites history; tags `pre-cache-purge-<ts>`. Run once if rebases trip on historical autosaves of `.cache/index.jsonl`.) |
| Print "history was force-pushed; sync your clone" prompt | `bin/post-rewrite-prompt.sh [<safety-tag>] [--reason="..."]` (read-only; emits the paste-into-other-sessions block. Defaults to most recent `pre-*` tag on origin.) |

## Invocation examples

```bash
# Per-task checkpoint (the 95% case):
bin/checkpoint.sh eng-1515-stack
bin/checkpoint.sh eng-1515-stack --status=in-review
bin/checkpoint.sh eng-1515-stack --status=blocked --next="Waiting on ENG-1514 DNS"
bin/checkpoint.sh eng-1515-stack --pr=11262
bin/checkpoint.sh eng-1621-foo --rename=wip-foo
bin/checkpoint.sh eng-1515-stack --include=README.md --include=bin/foo.sh   # task + sibling files in one commit

# Archive (active/ → archive/, marks status=archived, prepends Context line):
bin/archive.sh pillbutton-style-merge --pr=11246
bin/archive.sh wip-old --reason="superseded by eng-1700-bar"

# Autosave — PreCompact / SessionEnd hook, safe to run manually:
bin/autosave.sh

# Standup, filtered views:
bin/status.sh --since=yesterday
bin/status.sh --since=1.week.ago --project=new-marketing-page-serving
bin/status.sh --author=alice --since=1.week.ago
bin/status.sh --slug=eng-1515-stack            # single-task history
bin/status.sh --format=json                    # machine-readable

# Context packs:
bin/context.sh eng-1515-stack                  # default: resume-shaped
bin/context.sh eng-1515-stack --for=review     # reviewer-shaped
bin/context.sh eng-1515-stack --format=json

# Deterministic external-scan seeds for /worklog init --full:
bin/init-scan.sh
bin/init-scan.sh --format=json

# Slack context enrichment preview (dry-run; no writes):
bin/scrape-slack.sh --input=/tmp/slack-results.json --format=json
```

## Unix philosophy — one script, one thing

`bin/` helpers each do one job and compose via shell. Don't bolt survey/discovery logic onto `checkpoint.sh`; don't teach `autosave.sh` to pick slugs. If a new responsibility surfaces (rename detection, stale-task reaping, per-project reports), add a new script rather than widening an existing one.

The skill layer (`~/.claude/skills/worklog/`) is where multi-step orchestration lives; `bin/` stays small and sharp. Non-Claude agents compose these scripts directly from the shell.

## What each script writes

- `checkpoint.sh` — bumps `last_updated`, optionally updates `status`/`next_action`/`pr:`, commits + pushes. Auto-emits `Worklog-Status|Kind|Linear|PR|Project|Previous-Slug` trailers on transitions. `--include=<path>` (repeatable) stages sibling files (README, AGENTS.md, code) alongside the task file so a slug's task-file change and its repo edits land in one commit.
- `archive.sh` — moves the task file `active/` → `archive/`, sets `status: archived`, clears `next_action`, prepends `Archived YYYY-MM-DD: <reason>.` to `## Context`, commits + pushes. **Orphan-check:** refuses to archive if any active task still points at this slug via `parent_slug` / `supersedes` / `reopens` (directional, structural relations). `related[]` is a peer link and resolves fine to an archived target per AGENTS.md § Task relations, so it does **not** block archive. Reparent the children first, or set `WORKLOG_ARCHIVE_FORCE=1` to proceed anyway.
- `autosave.sh` — snapshot commit of anything dirty under your namespace; no-op if tree is clean.
- `status.sh` — **read-only**, emits markdown (standup-shape by default) or json. The default view groups by lifecycle bucket — shipped · in-review · in-flight · blocked — with shipped collapsed to a single slug/PR line and `next_action:` capped at the first sentence. `--format=grouped` switches to the legacy per-project × per-status view when an archive-heavy audit is the point. `--format=json` is machine-readable.
- `context.sh` — **read-only**, emits a per-slug pack with frontmatter + recent commits + live PR states (queries GitHub for each PR in `pr:`).
- `reconcile-pr.sh` — **read-only**, resolves PR linkage from authoritative `Worklog-PR:` trailers, fetches current GitHub state, and emits JSON with expected state, observed state/time/source, and mismatches. Repository resolution prefers `pr_repos`, then `WORKLOG_KNOWN_REPOS`, then a matching local clone remote under `PROJECTS_DIR`; it never edits or checkpoints the task.
- `init-scan.sh` — **read-only**, emits exact Linear issue identifiers, Notion targets, and PR numbers from active task files so `/worklog init --full` can prefer direct fetches over fuzzy semantic scans. Cold-start safe: returns zero tasks when `people/<ldap>/active/` does not exist yet.
- `scrape-slack.sh` — **dry-run by default**, matches captured Slack messages/threads to worklog tasks and emits proposed redacted summaries plus `external_refs: [{platform: slack, url, note}]`. Workspace-agnostic: it uses the target clone's resolved LDAP/SSO identity and reports searched/skipped workspaces plus auth limitations. With no provider/input it exits 0 as `status: unavailable`. Private surfaces require explicit `--include-dms` / `--include-mpims`; peer-owned, archived, duplicate, ambiguous, or low-score matches are proposal-only/no-op.
- `lint.sh` — **read-only**, validates every task file: strict-YAML frontmatter (warn on block-scalar drift), kind ∈ documented set, status ∈ FSM, project grammar, last_updated format, relation resolution, related[] notes, archive/status consistency. Exit 1 on errors. `--cross-task` adds opt-in FSM/stale-review/undeclared-ref drift checks (see `docs/protocol.md § Cross-task checks`). `checkpoint.sh` calls per-file mode softly on each save (stderr warnings only; bypass with `WORKLOG_NO_LINT=1`).
- `boundary-lint.sh` — **read-only**, scans task/project markdown for clone-boundary drift declared in `.worklog-boundary.json`. This is for split-source hygiene (for example: OSS tracker terms appearing in a work tracker, or work task vocabulary appearing in an OSS tracker), not schema correctness. Profile shape: `schema`, `label`, `include`/`exclude` globs, `deny: [{pattern,note}]`, optional `allow: [{path,pattern}]`, and `ignore_case` (default true). Use `allow` for narrow, intentional provenance exceptions such as an OSS port task citing the work source it extracted from; do not delete useful provenance just to make the guard pass. Exit 1 on matches. `bin/audit.sh --section=boundary` runs it automatically when a profile exists.
- `task-guard.sh` — **read-only**, classifies dirty task files against claimed slug(s). `--slug=<slug>` may repeat; `--include=<path>` explicitly allows an additional dirty task path; `--format=json` emits `{claimed_slugs, dirty_task_paths, foreign_task_paths, dirty_tasks}`. Exits 2 when a dirty task file belongs to another slug, so Codex/skill write paths can treat it as a mutex held by another session and avoid broad autosave/staging.
- `git-hooks/pre-commit` — path-filtered blocking hook. Runs per-file lint on staged task files, `tests/export/test_scrubber.sh` if the export pipeline changed, and `tests/frontmatter/test_round_trip.sh` if the frontmatter parser changed. ~95% of commits skip via path-filter. Bypass with `WORKLOG_NO_HOOK=1`.
- `git-hooks/post-commit` — TTL'd cross-task advisory. Fires after every commit; runs `"$WORKLOG_BIN/lint.sh" --cross-task` at most hourly (mtime gate on `.cache/cross-task.stamp`); emits warning/error counts to stderr. Never blocks. Inspect details with `"$WORKLOG_BIN/lint.sh" --cross-task` or `/worklog lint --cross-task`.

Both git hooks are wired by `"$WORKLOG_BIN/install-hooks.sh" --write` (sets `core.hooksPath` to the skill's absolute `git-hooks` directory). No CI workflow today — local hooks only; add a workflow if "enforced not encouraged" becomes load-bearing.
- `index.sh` — writes `.cache/index.jsonl` — one JSON record per task with flattened frontmatter + `body_refs.{prs,linear,slugs}`. **Derivative, never committed** (see `.gitignore`). Regenerate any time; `children.sh`, `pr.sh`, `stale.sh` auto-refresh when stale (>5 min by default; override with `WORKLOG_INDEX_MAX_AGE`).
- `children.sh` — reverse-index lookup for `parent_slug`, `supersedes`, `reopens`, and (with `--include-refs`) `related[]` + body mentions. Replaces hand-rolled `grep parent_slug: …` recipes.
- `pr.sh` — find every task referencing a PR number in frontmatter `pr:` or body `#N`.
- `stale.sh` — active tasks whose `last_updated` is ≥ N days old. Sorted oldest first.
- `audit.sh` — **read-only** composite health report. Sections: stale (`stale.sh`), blocked ≥7d, in-review ≥14d, cross-task drift (`lint --cross-task`), boundary drift (`boundary-lint.sh` when configured), and command-surface drift. Always exits 0 — report, not gate. Use `--section=<name>` to scope.
- `refactor.sh` — cross-task slug rename. Extends `bin/checkpoint.sh --rename` to also rewrite references in other task files (`parent_slug`, `related[].slug`, `supersedes`, `superseded_by`, `reopens`, body mentions). Word-boundary safe. Single squash-shaped commit. Dry-run by default; `--apply` to commit.
- `pre-commit-scan.sh` — staged-additions scan for typed-prefix secret tokens (`ghp_`, `sk-`, `github_pat_`, `xox*`, `AIza`, `AKIA`). Mirrors the regex set in `bin/export-setup.sh::scrub()`. Advisory by default; `WORKLOG_STRICT_SCAN=1` to block; `WORKLOG_NO_SCAN=1` to bypass. Wired into `bin/git-hooks/pre-commit` so checkpoint, archive, and hand-commits all flow through it.
- `_lib.sh::verify_provenance` — first-commit-per-clone guard: compares `resolve_ldap` against `git config user.email`'s local part. Match → emit `.cache/provenance-verified` sentinel (steady-state cost is zero). Mismatch → exit 1 with the suggested `git config` fix. Bypass: `WORKLOG_SKIP_PROVENANCE=1`. Called by `bin/checkpoint.sh` and `bin/archive.sh`.
- `checkpoint-batch.sh` — atomic multi-task frontmatter update. Reads JSON array from stdin (`[{slug, status?, next?, pr?}, ...]`); rewrites every touched task's frontmatter; emits a single `worklog-batch: N tasks updated` commit with one Worklog-Slug: trailer per touched slug + Worklog-Status: per status flip. One push instead of N. Saves log noise when flipping many tasks at once (e.g. closing out a sprint or graduating in-review tasks). Sibling to `bin/checkpoint.sh` (Unix one-script-one-job — see AGENTS.md § Helpers).
- `slug.sh` — closest-match slug lookup. `bin/slug.sh <fragment>` returns the best match across `people/*/{active,archive}/`; `--all <fragment>` lists scored matches. Match policy: exact → substring → Levenshtein (capped at 50% fragment-length distance). Used by `bin/git-hooks/commit-msg` to suggest fixes for typo'd `Worklog-Slug:` trailers; ready for any future tooling.
- `sql.sh` — per-slug SQL library. `list [<slug>]` enumerates committed queries; `show <slug> <name>` cats the SQL; `run <slug> <name> [--no-cache]` executes via `bq` against `ideogram-prod` (or `ideogram-staging` per `-- @env:`) and caches JSON response to `.cache/queries/<slug>/<name>.json`; `new <slug> <name>` scaffolds a header. Refuses to run queries containing literal email or long base64-shaped tokens (PII guard). Cache exists so design-doc reviewers read the same numbers the author saw. See AGENTS.md § Per-slug SQL libraries.
- `log-digest.sh` — burst-folded **read-only** projection of `git log`. Collapses ≥`--min-burst` (default 3) consecutive same-slug `<slug>: checkpoint` commits within `--burst-window` (default 4h) into a single digest entry showing the `next_action` trail. Status / create / archive commits split bursts. Filters: `--slug=<slug>`, `--since=<git-date>`, `--until=<git-date>`. Output: `--format=md` (default) or `--format=json`. `--obsidian-links` emits body slug refs as `[[slug]]` for vault use. Never rewrites history — that's `bin/log-compact.sh`. Use git-date syntax (`7.days.ago`, `2026-04-01`); bare `Nd` / `Nh` shortcuts do NOT work.
- `auto-slug-link.py` — body-only Obsidian wikilink converter. Walks task files, replaces bare `<slug>` body mentions with `[[<slug>]]`. Frontmatter byte-identical (bare-slug there is load-bearing per AGENTS.md:175 — `_index.py`, `_lint.py`, `children.sh`, `archive.sh` parse bare slugs). Skips fenced code, inline code, and already-wrapped slugs. Idempotent. Dry-run by default; `--apply` to write; `--file=PATH` / `--slug=SLUG` to scope. Grep-as-index invariant holds because `<slug>` is a substring of `[[<slug>]]`.
- `install-hooks.sh` — idempotently merges a `PreCompact` hook into `~/.claude/settings.json` pointing at `bin/autosave.sh`. Dry-run by default; `--write` applies. `--uninstall` reverses. Claude Code only — other harnesses have no equivalent hook; they rehydrate by re-reading the task file after compaction (see `docs/protocol.md § Surviving compaction`).
- `e2e.sh` — image-agnostic end-to-end fixture: 18 steps that seed tasks, exercise checkpoint/lint/archive, round-trip export, run regression tests, and verify the git-hooks (pre-commit + post-commit) fire correctly. Asserts on exit code or substring; first failure dumps last 30 lines of context. Designed for `Dockerfile.{debian,alpine}`; can also run on a fresh clone outside docker once `USER` and a local bare origin are set.
- `e2e-docker.sh` — parallel build/run wrapper around `Dockerfile.debian` (glibc + GNU coreutils) and `Dockerfile.alpine` (musl + busybox + apk coreutils). Default: parallel both. `--serial` for debugging; `debian` or `alpine` to scope. Per-image logs at `/tmp/e2e-${label}.log`. Warm: ~6s. Layer-cached cold: ~3s. Fully cold (apt/apk fetch): 45–90s per image.

## Query tools — `rg` (ripgrep) vs. `grep`

For **ad-hoc interactive queries**, prefer `rg` (ripgrep):

```bash
rg --type md '^parent_slug: eng-1515' people/         # fast, gitignore-aware, smart case
rg --type md --json 'status: in-review' people/       # structured output
rg -l 'ENG-1515' people/                              # list matching files
```

Why: `rg` is meaningfully faster on large corpora, respects `.gitignore` (skips `.cache/`), has smart-case and `--type md` built in, and emits JSON output for piping into `jq`.

**`rg` is NOT a runtime dependency of `bin/*`.** Scripts under `bin/` use `python3`, `grep`, `awk`, `jq` only — this keeps the repo runnable on any machine with a POSIX shell + Python, including CI runners without extra installs. If you write a new `bin/*` script, do not reach for `rg`; use `grep` / `python3` / `jq` so the dependency surface stays minimal.

Install ripgrep locally for ad-hoc use: `brew install ripgrep` (macOS) or `apt install ripgrep` (Debian/Ubuntu).
