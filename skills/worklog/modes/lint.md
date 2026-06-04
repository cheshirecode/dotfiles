# Mode: `lint`

Validate task files. Per-file by default; opt-in cross-task drift checks with `--cross-task`.

**Does not run the preamble.** Read-only operation.

## Forms

```
/worklog lint                    # per-file format on every people/*/{active,archive}/*.md
/worklog lint --cross-task       # adds opt-in FSM/stale-review/undeclared-ref checks
/worklog lint --fix-related      # auto-stub: append body-mentioned slugs to related: with placeholder note
/worklog lint --file=<path>      # single file (used by checkpoint.sh internally)
/worklog lint --format=json      # machine-readable output
```

## What per-file mode checks

`bin/_lint.py` validates strict-YAML frontmatter against the schema in AGENTS.md / docs/protocol.md § Lint rules:

- Frontmatter exists and parses.
- `slug` matches grammar; `kind` ∈ KINDS; `status` ∈ FSM; `last_updated` is `YYYY-MM-DD`.
- `next_action` is single-line.
- `repos` (if present) is a list.
- `project` (if present) is `none` or lowercase-kebab.
- Relations resolve: `parent_slug`, `supersedes`, `superseded_by`, `reopens`, every `related[].slug`.
- `related[]` entries have a `note`.
- Files under `archive/` should have `status: archived` (warn).

Errors → exit 1. Warnings → exit 0.

## What `--cross-task` adds

Active tasks only — archive/ is frozen history.

Errors:
- `status: blocked` requires `next_action` to start with `Waiting on` (FSM contract).

Warnings (heuristic):
- `status: in-review` for ≥14d with no `Worklog-PR:` trailer in `git log` for the slug — PR likely landed/abandoned without status flip.
- Body mentions a known slug not declared in `parent_slug` / `related[].slug` / `supersedes` / `superseded_by` / `reopens` (undeclared cross-task ref).

Driven by `git log --grep="Worklog-Slug: <slug>"` for the trailer check, so it's slower than per-file. Run before archive or as a periodic sweep — not on every checkpoint.

## What `--fix-related` does (auto-stub)

Companion to the body-mention warning above. Implies `--cross-task`. For each active task, scans the body for known sibling slugs not declared in any relation field, and appends them to the file's `related:` block with a placeholder note (`"(auto-added; refine note)"`). Refuses to touch files where `related:` is in inline-list form.

Flow: write the body referencing whatever sibling slugs the prose calls for, run `/worklog lint --fix-related`, then refine the placeholder notes to describe the actual relation. Removes the friction of manually mirroring body content into structured frontmatter.

The post-commit advisory (`bin/git-hooks/post-commit`) suggests this command automatically when body-mention warnings are detected.

## When to run

- **Auto:** `bin/checkpoint.sh` runs `bin/lint.sh --file=<path>` softly on every save (stderr-only; bypass with `WORKLOG_NO_LINT=1`).
- **On demand:** `/worklog lint` for full corpus before a major sweep or pre-archive.
- **Periodic:** `/worklog lint --cross-task` weekly or before archiving a long-running task.

## Output

Direct passthrough from `bin/lint.sh`. Markdown by default, JSON with `--format=json`. Exit code propagates.

```
Scanned 100 task files — 0 errors, 10 warnings

people/cheshirecode/archive/legacy.md  [archive]
  warn    kind 'fix' not in current documented set (legacy archive value)

people/cheshirecode/active/exploratory.md  [active]
  warn    missing project: (use 'none' if intentional)
```
