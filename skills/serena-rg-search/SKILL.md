---
name: serena-rg-search
description: Pick the right tool for multi-faceted code search across symbols, text, semantic meaning, JSON, git history, and logs. Use when finding definitions, references, files, strings, concepts without known terms, structured config, when-it-changed, or log events; or when planning a search workflow before reading code.
---

# serena-rg-search

Skip when one literal or known-file lookup is sufficient.

## Route first

Text-lane searches go through `zg` (zvec-grep) when installed: `zg query --rg`
is managed ripgrep, `--fts` adds BM25 ranking, and the bare form adds semantic
search. If `command -v zg` is empty, every `zg query --rg` below degrades to
plain `rg` — fall back and continue, don't block on setup.

**Caveats measured against zvec-grep 0.2.1:**

- `zg query --rg` exits 0 when it finds nothing (`No matches.`); `rg` exits 1.
  Read output and preserve existing scripts that branch on rg's exit status.
- Indexed lanes always return hits by nearest ranking and cannot express
  "not here." Confirm an absence with `--rg`/`rg`; ranked hits are candidates.
- `--fts` needs the index too: both indexed lanes fail
  `WORKSPACE_INDEX_NOT_FOUND` without one. Only `--rg` works unindexed.

## Decision Rule

Match the question to the facet, then the tool:

| Facet | Tool |
|---|---|
| Literal text, regex, filenames, broad discovery | `zg query --rg` (fallback `rg` / `rg --files`) |
| Concept or behavior, exact terms unknown | `zg query "natural language"` (semantic; `--fts` for keyword-ranked) |
| Known symbol, references, file structure | Serena (`find_symbol`, `find_referencing_symbols`, `get_symbols_overview`) |
| Structured JSON (OpenAPI, package.json, API payloads) | `jq` (often piped from `rg --files`) |
| "When did this appear / disappear / change" | `git log -S` (pickaxe), `git log -G` (regex), `git log -p -- path` |
| Logs, traces, time-windowed events | `rg` on the file, `journalctl` (linux), `log show` (mac) |

Default hybrid flow for unfamiliar code: `rg` to find candidates → Serena for the symbol → `git log -S` to see how it got there. Fall back to `rg` if Serena isn't activated for the project.

For command examples after selecting a facet, read
[references/commands.md](references/commands.md). Narrow noisy searches by
path, type, or glob before reading full files; switch to symbols when exact
references matter.

## Tool Availability

Check each required binary separately:

```bash
for t in zg rg jq; do command -v "$t" >/dev/null 2>&1 || echo "missing: $t"; done
```

`command -v zg rg jq` succeeds when any one exists; test each tool separately.

Use available fallbacks; do not install tools just to perform a search.
For an explicit `zg` setup request, install `@zvec/zvec-grep` with Node 22+
and run `zg index` for indexed lanes; ignore `.zvec-grep/` in Git.

Find Serena in the session's MCP tools (`serena__find_symbol`), not with
`command -v`. If unavailable, use `rg` without attempting setup mid-task.

**Serena MCP setup:** Only for a setup request, read `references/mcp-setup.md`.
