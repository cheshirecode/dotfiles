# Graph navigation

Requires Python 3.12+ and an already provisioned environment. Set `skill_dir`,
`checkout`, and `tool_env` to the installed skill, target Git checkout, and
separate Graphify virtual environment. These are caller-supplied paths.

```sh
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" status
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" query "parsing"
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" explain "parse_record"
python3 "$skill_dir/scripts/graph.py" --repo "$checkout" --environment "$tool_env" path "parse_record" "format_record"
```

Pass identical repeated `--exclude 'glob'` options before the command on every
invocation. Patterns match checkout-relative paths using Python `fnmatchcase`;
`*` can match `/`. Exclusion changes invalidate the accepted graph. Graphify's
own parser support determines language coverage; a graph miss is not absence.

The selected corpus is tracked plus nonignored untracked regular files, with
missing/deleted files omitted. Ignored untracked files are not indexed. Symlinks
and submodule directories must be explicitly excluded; index another checkout
separately when needed. Caller exclusions can narrow the corpus by language.
Graphify may further filter unsupported files or honor its own ignore rules.

`--state` may select an external private directory. State must not live in the
source tree outside Git metadata, and cannot be reused across physical checkouts.
The installed tool environment must also be outside source. Graphify receives a
private source snapshot; map its `source/` suffix back to the original checkout
when reading/citing results. Retained snapshots contain source code: preserve
local confidentiality and do not commit or upload state/logs.

`refresh` is explicit. Failed builds preserve the accepted generation; stale
queries fail rather than displaying old evidence. Full output goes to local
logs; the printed preview is at most 8000 bytes and includes exit status and
artifact location. A nonzero command returns nonzero. Use `rg`/Serena directly
when graph search fails; the launcher does not guess a fallback query.

Generations/logs are retained for diagnosis. No automatic cleanup is performed.
The freshness check hashes contents, selected file names, exclusions, installed
package versions, and launcher/requirements contents. It is a consistency check,
not protection against a malicious local process or an edit-and-revert race.
