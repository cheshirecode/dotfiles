---
name: serena-rg-search
description: Pick the right tool for multi-faceted code search across symbols, text, JSON, git history, and logs. Use when finding definitions, references, files, strings, structured config, when-it-changed, or log events; or when planning a search workflow before reading code.
---

# Serena Rg Search

Use this skill to pick the fastest search approach for a coding task. Most real questions touch more than one facet — combine tools deliberately instead of reflexively reaching for `rg`.

## Decision Rule

Match the question to the facet, then the tool:

| Facet | Tool |
|---|---|
| Literal text, regex, filenames, broad discovery | `rg` / `rg --files` |
| Known symbol, references, file structure | Serena (`find_symbol`, `find_referencing_symbols`, `get_symbols_overview`) |
| Structured JSON (OpenAPI, package.json, API payloads) | `jq` (often piped from `rg --files`) |
| "When did this appear / disappear / change" | `git log -S` (pickaxe), `git log -G` (regex), `git log -p -- path` |
| Logs, traces, time-windowed events | `rg` on the file, `journalctl` (linux), `log show` (mac) |

Default hybrid flow for unfamiliar code: `rg` to find candidates → Serena for the symbol → `git log -S` to see how it got there. Fall back to `rg` if Serena isn't activated for the project.

## Prefer `rg` For

Unknown locations, string/regex, non-code files, broad scans, quick file listing.

```bash
rg -n "useUserTaskQuotaStats" frontend/react/src
rg -n "announcement_text" openapi packages/api-client/src
rg --files | rg 'announcement'
rg -U 'pattern\n.*other' path/   # multiline
```

## Prefer Serena For

Exact symbol lookup, references, file overview before editing.

- `find_symbol` — known function/class/hook
- `find_referencing_symbols` — usages
- `get_symbols_overview` — file map
- `search_for_pattern` — only as a scoped fallback after symbolic tools

## Prefer `jq` For

JSON where keys and shape matter, not just substrings. Combine with `rg --files` to locate, then `jq` to extract.

```bash
jq '.paths | keys[]' openapi/spec.json
jq '.dependencies | to_entries[] | select(.value | test("^\\^?1\\."))' package.json
rg --files -g '*.json' | xargs -I{} jq -r 'select(.kind=="X") | input_filename' {} 2>/dev/null
```

Stay in `rg` if you only need to know whether a string appears.

## Prefer `git log` For

History-aware questions: when, why, by whom.

```bash
git log -S 'announcement_text' -- path/         # pickaxe: commits that add/remove the string
git log -G 'use\w+Quota' -- frontend/           # regex over diff content
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

- `rg` is the best first pass; Serena the best second pass.
- On noisy `rg` hits: narrow the file, then switch to Serena.
- Stay in `rg` for YAML/generated artifacts; switch to `jq` only when shape matters.
- `git log -S` beats guessing — use it before claiming "this used to work."
- Avoid reading full files until search has narrowed the target.

## Worked Examples

- "Where is this hook defined?" → `rg` → Serena `find_symbol`.
- "Who calls `handleGenerationErrors`?" → Serena `find_referencing_symbols`.
- "Find `announcement_text` across OpenAPI and generated clients." → `rg`.
- "What endpoints does this OpenAPI spec expose?" → `jq '.paths | keys[]'`.
- "When did `useUserTaskQuotaStats` get added?" → `git log -S 'useUserTaskQuotaStats'`.
- "Why is the worker erroring at 3am?" → `rg`/`journalctl` on the log with a time window.
- "Understand this file before editing." → Serena `get_symbols_overview`.

## Tool Availability

`rg` and `jq` aren't preinstalled everywhere. Check before use:

```bash
command -v rg jq
```

If missing: `brew install ripgrep jq` (macOS) · `apt-get install ripgrep jq` (Debian) · `dnf install ripgrep jq` (Fedora) · `pacman -S ripgrep jq` (Arch). `git` is assumed present in any repo. Serena is provided by the MCP server — if it isn't activated for the project, fall back to `rg` and don't block on it.
