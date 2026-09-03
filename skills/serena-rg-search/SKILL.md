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

- Concept known but exact terms unknown ("where is X validated?"): `zg query
  "natural language"` — semantic + FTS hybrid, needs `zg index` once per
  workspace (index lives in `.zvec-grep/`, keep it gitignored).
- Unfamiliar codebase or broad discovery: start with `zg query --rg` (or `rg`),
  then escalate to Serena for symbol-aware follow-up.
- Known symbol, references, or file overview: start with Serena (`find_symbol`, `find_referencing_symbols`, `get_symbols_overview`).
- Structured JSON shape (keys, nesting, API payloads): use `jq`, optionally piped from `rg --files` to locate files.
- History-aware ("when did this appear/change"): use `git log -S` / `-G` / `-p`.
- Runtime logs or time-windowed events: `rg` on the log file, or `journalctl` / `log show`.
- Serena MCP not activated: fall back to `rg`; do not block. See `references/mcp-setup.md` to set it up.

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

## Prefer `zg` For

Unknown locations, string/regex, non-code files, broad scans, quick file
listing — and anything where you know the concept but not the tokens.

```bash
zg query --rg -n "useUserTaskQuotaStats" frontend/react/src   # managed rg; note exit 0 on no match
rg --files | rg 'announcement'                # NOT `zg query --rg --files`:
                                              # "--files changes rg output and
                                              # cannot be used with managed --rg"
zg query --fts "announcement text banner"     # BM25-ranked keyword search
zg query "where user quota limits are enforced"   # semantic (needs `zg index`)
zg index                                       # build/refresh workspace index
zg status                                      # index freshness
```

Semantic hits come back ranked with `file:line` spans and the matching lane
(`matchedBy=fts+vector`), so they chain into Serena/`git log` like rg hits do.
Without `zg`, use plain `rg` — every `--rg` example above takes identical
flags (`-U` multiline, `-t` type, `-g` glob).

## Prefer Serena For

Exact symbol lookup, references, file overview before editing.

- `find_symbol` — known function/class/hook
- `find_referencing_symbols` — usages
- `get_symbols_overview` — file map
- `search_for_pattern` — plain regex scan over project files. **Not** symbol-aware and not
  index-backed: it is `rg` with a different scoping vocabulary (`relative_path` to limit to a
  file or subtree, `paths_include_glob` / `paths_exclude_glob` to filter, and
  `restrict_search_to_code_files` to skip docs and fixtures). Reach for it because you are
  already in Serena and want the hit in the same tool surface as the symbol calls — not
  because it understands symbol boundaries. If you are out of Serena, `rg` is equivalent.

## Prefer `jq` For

JSON where keys and shape matter, not just substrings. Combine with `rg --files` to locate, then `jq` to extract.

```bash
jq '.paths | keys[]' openapi/spec.json
jq '.dependencies | to_entries[] | select(.value | test("^\\^?1\\."))' package.json
rg -g '*.json' -l '"kind"\s*:\s*"X"'   # find JSON files containing a key/value pair
```

Stay in `rg` if you only need to know whether a string appears.

## Prefer `git log` For

History-aware questions: when, why, by whom.

```bash
git log -S 'announcement_text' -- path/         # pickaxe: commits that add/remove the string
git log -G 'use\w+Quota' --perl-regexp -- frontend/  # PCRE regex over diff content
git log -p -- path/to/file                      # full diff history of a path
git log --follow -- path/to/file                # survive renames
```

Use this before claiming a regression — confirm the change actually exists in history.

## Prefer Log Tools For

Runtime events, not source code.

- `rg -n PATTERN file.log` — first pass on any log file; supports `-U` for multiline stack traces and `-A`/`-B` for context.
- `journalctl -u <unit> --since '1h ago' | rg PATTERN` — linux systemd services.
- `log show --predicate 'eventMessage CONTAINS "X"' --last 1h` — macOS unified log.
- `tail -f file.log | rg --line-buffered PATTERN` — follow live.

For deep interactive exploration consider `lnav`, but `rg` + a time filter usually suffices for an agent.

## Practical Heuristics

- `zg` (or `rg`) is the best first pass; Serena the best second pass. When a
  literal first pass returns nothing, try the semantic lane before concluding
  the thing doesn't exist — the term may simply be named differently.
- On noisy `rg` hits: narrow with `-t` (type) or `-g` (glob), then switch to Serena for symbol-aware filtering.
- Stay in `rg` for YAML/generated artifacts; switch to `jq` only when shape matters.
- `git log -S` beats guessing — use it before claiming "this used to work."
- Avoid reading full files until search has narrowed the target.
- When `rg` returns 50+ hits, switch strategy: add path restrictions, use `-g`/`-t` filters, or escalate to Serena's symbol tools.

## Worked Examples

- "Where is this hook defined?" → `rg` → Serena `find_symbol`.
- "Who calls `handleGenerationErrors`?" → Serena `find_referencing_symbols`.
- "Find `announcement_text` across OpenAPI and generated clients." → `rg`.
- "What endpoints does this OpenAPI spec expose?" → `jq '.paths | keys[]'`.
- "When did `useUserTaskQuotaStats` get added?" → `git log -S 'useUserTaskQuotaStats'`.
- "Why is the worker erroring at 3am?" → `rg`/`journalctl` on the log with a time window.
- "Understand this file before editing." → Serena `get_symbols_overview`.

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
