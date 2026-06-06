# Mode: `project`

Multi-task projects with declaration-order sequencing, `depends_on:` dep graph, and per-task advisory mutex (file-based, session-id arbitrated). Design lives in the `worklog-project-mode` task; this file is the dispatch surface.

**Preamble: minimal.** Resolve LDAP. The driver `"$WORKLOG_BIN/project.sh"` handles its own validation. Read-only subcommands (`list`, `verify`, `next`) skip the worklog repo pull; mutating subcommands (`new`, `claim`, `release`, `reap`) rely on the standard preamble pull-first discipline (run preamble step 3 yourself before invoking).

## Subcommands

| Form | Notes |
|---|---|
| `"$WORKLOG_BIN/project.sh" new <slug> --goal=... --objective=... [--repos=a,b] [--stale-after=30m] [--dry-run]` | Read tasks-JSON on stdin (preferred) or `--tasks-json=...`. Writes the `kind: project` parent + child stubs. `--dry-run` prints the would-be files. |
| `"$WORKLOG_BIN/project.sh" next <slug>` | Print first claim-eligible child (deps satisfied + not held by a different session). Exit 1 with reason if nothing eligible. |
| `"$WORKLOG_BIN/project.sh" claim <child-slug> [--dry-run]` | Claim a task. Pre-commit arbitrates: rejects if on-disk claim is non-stale + different session. `--dry-run` returns `CLAIM_OK` / `LOCKED_BY=<holder>` / `STALE=...` without writing. |
| `"$WORKLOG_BIN/project.sh" claim next <slug>` | Combo: `next` then `claim`. Walks past locked tasks. |
| `"$WORKLOG_BIN/project.sh" release <child-slug>` | Clear your own claim. Idempotent. |
| `"$WORKLOG_BIN/project.sh" reap [--session=<id>] [--stale=<dur>]` | Clear claims whose heartbeat is stale (default 30m). With `--session=<id>` cascades — clears every task that session holds. |
| `"$WORKLOG_BIN/project.sh" verify <slug> \| --all` | Dep cycles, parent_slug ↔ tasks consistency, orphan claims. Exit `0`/`1`/`2` for clean/warnings/errors. |
| `"$WORKLOG_BIN/project.sh" list` | Projects + child task rollup (`<slug>  [<status>]  (N tasks: <status counts>) held=K`). |

## Tasks-JSON shape

Each task is a `{slug, [title], [kind], [depends_on], [repos]}` object:

```json
[
  {"slug": "foo", "kind": "impl"},
  {"slug": "bar", "kind": "impl", "depends_on": ["foo"]},
  {"slug": "baz", "kind": "impl", "depends_on": ["foo"]}
]
```

Children inherit the project's `--repos` unless they declare their own. `depends_on:` lives only in the parent's `tasks:` block — child stubs do **not** carry a top-level `depends_on:`.

## Workflow

1. `"$WORKLOG_BIN/project.sh" new <slug> --goal=... --objective=... --repos=cheshirecode/<repo>,cheshirecode/<repo> < tasks.json` — paraphrase a `/stacking-strategy` (cheshirecode/<repo> repo) output into the JSON shape, or hand-write for non-code work.
2. `"$WORKLOG_BIN/project.sh" next <slug>` — pick the next eligible child.
3. `"$WORKLOG_BIN/project.sh" claim <child-slug>` — take the lock (one-line commit with `Worklog-Claim:` trailer).
4. Work the task; `"$WORKLOG_BIN/checkpoint.sh" <child-slug>` advances frontmatter `heartbeat_at:` automatically.
5. `"$WORKLOG_BIN/archive.sh" <child-slug> --reason=shipped --summary=...` when done (clears the claim, marks status archived).
6. `"$WORKLOG_BIN/project.sh" next <slug>` again → next eligible.

When the whole conversation dies mid-task, claims clear automatically after `mutex.stale_after` (default 30m) on the next `"$WORKLOG_BIN/project.sh" reap`.

## Cross-host (Claude Code + Codex + Cursor)

Session ID resolution per host (`bin/_lib.sh::resolve_session_id`):

| Host         | source                                                                                  |
|--------------|-----------------------------------------------------------------------------------------|
| Claude Code  | `$CLAUDE_CODE_SESSION_ID` (propagates to sub-agents unchanged — verified 2026-05-12)    |
| Codex CLI    | `$CODEX_SESSION_ID` / `$OPENAI_SESSION_ID` if set, else machine UUID                    |
| Cursor       | `$CURSOR_SESSION_ID` if set, else machine UUID                                          |
| Fallback     | UUID persisted at `~/.config/worklog/session-id` (per-machine, coarse)                  |

Parent + N Claude Code sub-agents share one session ID — same-session re-claim is idempotent; sub-agents don't collide with their parent. Cross-host (Claude ↔ Codex on the same machine) goes through `flock` + pre-commit arbitration.

## Output / writes

- `new` writes 1 project file + N child stubs in one atomic commit (subject `<slug>: create project`, per-child `Worklog-Slug:` trailers). Auto-syncs `tasks:` → `related:` block on the project so cross-task lint resolves clean.
- `claim` writes a single commit modifying one child task's frontmatter `claim:` block, with a `Worklog-Claim:` trailer.
- `release` / `reap` clear `claim:` and emit `Worklog-Release:` / `Worklog-Reap:` trailers respectively.

## Acceptance / tests

`tests/project/test_phase{1,2,3}.sh` are the canonical e2e harness:

- Phase 1: 3-task A→B→C chain walks via `next` + `archive`.
- Phase 2: two distinct session IDs claim distinct tasks; stale claim reaped after `mutex.stale_after`.
- Phase 3: `verify --all`, `list`, stacking-strategy markdown parser, Cursor fallback UUID.

## Out of scope (deferred)

- Mechanical `/stacking-strategy` markdown parser is shipped (`"$WORKLOG_BIN/_stacking_strategy_parser.py"`) but `project new` doesn't invoke it automatically — agent paraphrases into JSON. Wire it in when the manual paraphrase step bites.
- Phase 2 mutex acceptance tests pass; real cross-host (Claude ↔ Codex concurrent on Fred's box) hasn't fired yet. Watch for the first contention.
