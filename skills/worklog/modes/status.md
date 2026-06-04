# Mode: `status`

Thin wrapper around `bin/status.sh`. Read-only — never writes.

Pass-through flags:

| Flag             | Default                   | Meaning                                                          |
| ---------------- | ------------------------- | ---------------------------------------------------------------- |
| `--since=<date>` | `midnight`                | any git-parseable date (`yesterday`, `1.week.ago`, `2026-04-15`) |
| `--author=cheshirecode`| self (resolved in preamble) | peer standups (read-only — only reads `people/cheshirecode/`)       |
| `--slug=<slug>`  | —                         | full per-task history; follows `Worklog-Previous-Slug` renames   |
| `--format=...`   | `markdown`                | `markdown` or `json`                                             |
| `--include-meta` | off                       | keep `protocol:/bin:/docs:` subjects (off = filter them as noise)|

Invocation: `cd $PROJECTS_DIR/_worklog && bin/status.sh <flags>`. The script handles LDAP/repo resolution itself; the skill only runs the preamble and invokes.

Render the script's output verbatim to the user. If `--format=json` was requested, hand the JSON back without pretty-printing commentary.
