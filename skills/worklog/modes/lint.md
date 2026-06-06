# Mode: `lint`

Pure dispatch. Read-only (except `--fix-related`).

```bash
cd "$WORKLOG_REPO" && "$WORKLOG_BIN/lint.sh" "$@"
```

Pass-through flags (see `"$WORKLOG_BIN/lint.sh" --help`): `--cross-task`, `--fix-related`, `--file=<path>`, `--format=markdown|json`.

`--fix-related` writes (auto-stubs `related:` entries from body slug mentions); everything else is read-only. Render output verbatim. Exit code propagates.

Schema + check details live in `docs/protocol.md` § Lint rules — only consult when a check fails and you need to understand *why*.
