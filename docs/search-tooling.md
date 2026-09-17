# Search tooling

`zg` (zvec-grep) replaces bare `rg` for shell-level search in this repo. One
CLI, three lanes; results keep file:line locations:

- `zg query --rg <rg-args>` — managed ripgrep, with one difference that bites:
  **it exits 0 when it finds nothing, where `rg` exits 1.** So
  `rg X || echo absent` fires and the `zg` form never does; it prints
  `No matches.` instead. Read the output, not `$?`, and do not drop it into an
  existing script that branches on rg's exit status.
- `zg query --fts "terms"` — BM25 keyword ranking when literal hits are noisy.
  Needs the workspace index, same as the semantic lane.
- `zg query "natural language"` — semantic + FTS hybrid when you don't know
  the exact terms. Requires the workspace index (`zg index`; stored in
  `.zvec-grep/`; rebuild after large refactors). **`.zvec-grep/` is
  gitignored in THIS repo only.** Verified 2026-09-03: it is not ignored
  in /workspace/midas or /workspace/worklog, so indexing there drops a
  ~15M untracked directory into `git status`, one `git add -A` from being
  committed. Before `zg index` in any other repo, check
  `git check-ignore .zvec-grep` and add it (or set a global
  `core.excludesfile`) first. Without one, both
  this and `--fts` fail `WORKSPACE_INDEX_NOT_FOUND`; only `--rg` works
  unindexed.

**The ranked lanes cannot say "not here."** `--fts` and the semantic form
return the top N by ranking, so a query for something absent still comes back
full — `zg query --fts "xyzzy plugh frotz nitfol"` returns 10 hits. Use them to
find candidates; confirm an absence with `--rg` or `rg`, which can express one.
(Measured against zvec-grep 0.2.1.)

Gate on availability and fail open: if `command -v zg` is empty, use `rg` and
continue — never block on setup mid-task. Install: `npm install -g
@zvec/zvec-grep` (Node 22+). This governs Bash searches only; the harness
Grep/Glob tools are unchanged. Full facet routing (symbols, JSON, history,
logs) lives in `skills/serena-rg-search`.

