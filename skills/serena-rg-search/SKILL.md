---
name: serena-rg-search
description: Pick the right tool for multi-faceted code search across symbols, text, semantic meaning, JSON, git history, and logs. Use when finding definitions, references, files, strings, concepts without known terms, structured config, when-it-changed, or log events; or when planning a search workflow before reading code.
---

# serena-rg-search

Use this skill to pick the fastest search approach for a coding task. Most real questions touch more than one facet — combine tools deliberately instead of reflexively reaching for `rg`.

## When to use

- Finding definitions, references, files, strings, structured config, when-it-changed, or log events
- Planning a search workflow before reading code
- Multi-faceted search across symbols, text, JSON, git history, and logs

Skip if: one literal or known-file lookup is sufficient.

## Route first

Text-lane searches go through `zg` (zvec-grep) when installed: `zg query --rg`
is managed ripgrep, `--fts` adds BM25 ranking, and the bare form adds semantic
search. If `command -v zg` is empty, every `zg query --rg` below degrades to
plain `rg` — fall back and continue, don't block on setup.

**Three differences from `rg` that bite, all measured against zvec-grep 0.2.1:**

1. **`zg query --rg` exits 0 when it finds nothing; `rg` exits 1.** So
   `rg PATTERN || echo absent` fires the absent branch and
   `zg query --rg PATTERN || echo absent` never does. It prints `No matches.`
   instead. Read the output, not `$?` — and do not swap `zg query --rg` into an
   existing script that branches on rg's exit status.
2. **The indexed lanes always return hits.** `--fts` and the bare semantic form
   return the top N nearest by ranking, so a query for something absent still
   comes back full: `zg query --fts "xyzzy plugh frotz nitfol"` returns 10 hits.
   **These lanes cannot express "not here."** Confirm an absence with
   `--rg`/`rg`, which can; use the ranked lanes to find candidates, never to
   prove something does not exist.
3. **`--fts` needs the index too**, not just the semantic form: without one both
   fail `WORKSPACE_INDEX_NOT_FOUND`. Only `--rg` works unindexed.

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

`zg`, `rg`, and `jq` aren't preinstalled everywhere. Check before use:

```bash
for t in zg rg jq; do command -v "$t" >/dev/null 2>&1 || echo "missing: $t"; done
```

`command -v zg rg jq` looks like the same check and is not: it prints only the
tools it finds and **exits 0 as long as any one of them exists**, so a missing
`zg` reads as a clean result unless you count the lines. The loop names what is
absent and prints nothing when all three are present.

If `zg` is missing: `npm install -g @zvec/zvec-grep` (Node 22+) — or skip it
and use `rg`; never block a task on installing it. If `rg`/`jq` are missing:
`brew install ripgrep jq` (macOS) · `apt-get install ripgrep jq` (Debian) ·
`dnf install ripgrep jq` (Fedora) · `pacman -S ripgrep jq` (Arch). `git` is
assumed present in any repo. `zg`'s semantic lane also needs a one-time
`zg index`; its `.zvec-grep/` directory belongs in `.gitignore`.

Serena is an MCP server, not a binary — `command -v` will never find it. Check the session's tool list for a tool whose name ends in `serena__find_symbol` (Claude Code exposes it as `mcp__serena__find_symbol`); if no such tool is listed, Serena is not activated for this project — use `rg` and do not attempt setup mid-task.

**Serena MCP setup:** Serena is provided by the MCP server — if it isn't activated for the project, fall back to `rg` and don't block on it. To set up the Serena MCP server for Claude Code, Cursor, or OpenCode, read `references/mcp-setup.md`.
