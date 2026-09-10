# Search command cookbook

Read only for examples of the selected facet; resolve paths in the target repo.

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
