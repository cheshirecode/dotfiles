# CLAUDE.md

This repo's protocol for any agent (human or LLM) lives in [`AGENTS.md`](./AGENTS.md). Read it first.

For Claude Code specifically:

- The first-class command surface is the `/worklog` skill at `~/.claude/skills/worklog/SKILL.md`. Bare `/worklog` (or `/worklog help`) prints the subcommand menu.
- If the skill is not yet installed on this machine, follow `AGENTS.md` directly and use `bin/*` helpers — `bin/checkpoint.sh`, `bin/archive.sh`, `bin/status.sh`, `bin/context.sh`, `bin/lint.sh`. Each self-documents via `--help`.
- Hooks (`PreCompact`, `SessionEnd`) are wired by `bin/install-hooks.sh --write`. They run `bin/autosave.sh` + `bin/compact-kernels.sh` so the cross-session journal survives compaction.
- Vault layout: `people/<ldap>/{active,archive}/<slug>.md`. Slug is the join key — grep is the index. `project:` rollups live in `projects/<project>.md` (Dataview MOCs).

Everything else — slug grammar, FSM, commit trailers, relations, editing rules — is in `AGENTS.md` and `docs/protocol.md`. Don't duplicate here.
