# Mode: `status`

Pure dispatch. Read-only.

```bash
cd "$PROJECTS_DIR/_worklog" && bin/status.sh "$@"
```

Pass-through flags (see `bin/status.sh --help`): `--since=<date>`, `--author=<ldap>`, `--slug=<slug>`, `--format=markdown|json`, `--include-meta`.

Render output verbatim. JSON output → hand back unwrapped.
