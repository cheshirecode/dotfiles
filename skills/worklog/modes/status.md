# Mode: `status`

Pure dispatch. Read-only.

```bash
cd "$WORKLOG_REPO" && "$WORKLOG_BIN/status.sh" "$@"
```

Pass-through flags (see `"$WORKLOG_BIN/status.sh" --help`): `--since=<date>`, `--author=<ldap>`, `--slug=<slug>`, `--format=markdown|json`, `--include-meta`.

Render output verbatim. JSON output → hand back unwrapped.
