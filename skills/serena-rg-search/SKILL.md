---
name: serena-rg-search
description: Choose tools for multi-faceted code investigation across symbols, text, history and logs. Skip simple literal searches and known-file lookups.
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
| Cross-file callers, dependencies, or an unfamiliar change boundary | Scoped source search → resolve symbols/references with Serena → verify each relevant hop in source |
| Structured JSON (OpenAPI, package.json, API payloads) | `jq` (often piped from `rg --files`) |
| "When did this appear / disappear / change" | `git log -S` (pickaxe), `git log -G` (regex), `git log -p -- path` |
| Logs, traces, time-windowed events | `rg` on the file, `journalctl` (linux), `log show` (mac) |

For unfamiliar code, locate candidates with `rg`, then resolve the relevant
symbols/references with Serena. Add `git log` when history answers the question;
stop once current source supports the answer. Do not add an indexed tool merely
because it can represent the same relationships.

## Resolve ambiguity and verify

Scope to the relevant source paths before widening into tests, generated or
vendored code; use the target project's layout, not a fixed exclusion list.
For repeated names, resolve the file and containing class/module first. Use the
symbol identifier returned by the selected tool, with its own qualifier syntax;
a ranked or fuzzy hit is not an exact symbol match.

For relationship questions, inspect the actual call/reference at each relevant
hop and cite file/line evidence. Imports and containment establish structure,
not execution order or runtime reachability. Flag unresolved dynamic dispatch,
configuration, or unsupported-language boundaries instead of treating missing
results as proof of absence. Read the selected-facet examples below as needed.

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

If an index is missing/stale, a tool is unavailable, or results are ambiguous
or truncated, narrow the query or continue with current source search. Do not
install tools or rebuild indexes just to perform an ordinary search. Preserve
exit status and stderr when a tool fails; distinguish a search miss from a
permission, ownership, or runtime error before retrying. Report any remaining
coverage limit with the answer.
For an explicit `zg` setup request, install `@zvec/zvec-grep` with Node 22+
and run `zg index` for indexed lanes; ignore `.zvec-grep/` in Git.

Find Serena in the session's MCP tools (`serena__find_symbol`), not with
`command -v`. If unavailable, use `rg` without attempting setup mid-task.

**Serena MCP setup:** Only for a setup request, read `references/mcp-setup.md`.
