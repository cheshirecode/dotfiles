# Host capability routing

Read only for installation, delegation primitives, recurrence, or host-specific
tracking.

## Shared contract

- Keep `skills/loop-engineering/` as the single source.
- Use only standard `name` and `description` frontmatter in `SKILL.md`.
- Discover capabilities before invoking them.
- Preserve the same run contract and terminal statuses on every host.

## Codex

- Discover shared skills from `~/.agents/skills/`.
- Use the current task plan and available subagent tools for in-session tracking
  and bounded delegation.
- Invoke the installed `worklog` skill for durable context and checkpoints.
- For recurrence, use an available Codex automation or `loop-orchestrator`; if
  neither is callable, end `needs_human`.

## Claude Code

- Discover personal skills from `~/.claude/skills/`.
- Use the available task tracker and Agent tool for in-session tracking and
  bounded delegation.
- Invoke `/worklog context <slug> --for=compact` before cold delegation and
  pass the returned pack directly. Use `/worklog sync` for the protocol's
  confirmation/checkpoint boundary.
- Use Claude's real `/loop`, scheduled task, or hook capability only when exposed
  and authorized. Otherwise end `needs_human`.

## Cursor

- Discover user skills from `~/.agents/skills/` or Cursor's native
  `~/.cursor/skills/`; project-local alternatives may use `.agents/skills/` or
  `.cursor/skills/`.
- Use Cursor todos and subagents when exposed.
- Invoke the installed worklog skill or its documented helper commands for
  durable context. If unavailable, use one durable project tracker and label the
  fallback.
- Use a configured Cursor automation or hook only after verifying it exists and
  has a bounded stop rule. Otherwise end `needs_human`.

## Compatibility rule

Never encode a host-only hook, command substitution, tool name, or permission
grant in the portable root skill. Keep host differences in this reference and
degrade explicitly when a capability is absent.
