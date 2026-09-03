# Host capability routing

Read only for installation, delegation primitives, recurrence, or host-specific
tracking.

## Shared contract

- Keep `skills/loop-engineering/` as the single source.
- Use only standard `name` and `description` frontmatter in `SKILL.md`.
- Discover capabilities before invoking them.
- Preserve the same run contract and terminal statuses on every host.
- During an active invocation, keep cycling while state is `running`; progress
  updates are not pause points.
- Across invocations, continue only through a verified host recurrence
  primitive. A prompt cannot manufacture background execution.
- After intervention or a scheduled wakeup, the agent creates a successor state
  bound to the terminal predecessor and replays the stopping check before
  continuing. Treat supplied intervention as pending until that check passes.
- For duplicate installations, run `scripts/install_audit.py --canonical <skill-dir>`. `--link-identical` replaces only byte-identical directories; any divergent root fails the whole preflight before writes. Pass the clone the roots actually load from as `--canonical <dir>`; verify with `scripts/install_audit.py --root <dir> --dry-run`, then repair with `--apply`; on divergence report the mismatch. Exit `0` clean, `2` usage error, `3` divergence (prints diff). Use `--root` for non-standard installs, otherwise resolve from `$HOME/.claude/skills`, `$HOME/.agents/skills`, and project-local `.agents/skills/`.

## Codex

- Discover shared skills from `~/.agents/skills/` or `~/.codex/skills/`.
- Use the current task plan and available subagent tools for in-session tracking
  and bounded delegation.
- Keep issuing tool calls in the current task while state is `running`; do not
  yield merely because one cycle ended.
- Invoke the installed `worklog` skill for durable context and checkpoints.
- For recurrence, use an available Codex automation; if none is callable, end
  `needs_human`. Each heartbeat wakes the agent, which
  resumes from the prior `continue_scheduled` state instead of reopening it.

## Claude Code

- Discover personal skills from `~/.claude/skills/`.
- Use the available task tracker and Agent tool for in-session tracking and
  bounded delegation.
- Continue the current tool/agent sequence while state is `running`; do not end
  the response between authorized cycles.
- Invoke `/worklog context <slug> --for=compact` before cold delegation and
  pass the returned pack directly. Use `/worklog sync` for the protocol's
  confirmation/checkpoint boundary.
- Use Claude's real `/loop`, scheduled task, or hook capability only when exposed
  and authorized. Each recurrence wakes the agent to resume a bound successor.
  Otherwise end `needs_human`.

## Cursor

- Discover user skills from `~/.agents/skills/` or Cursor's native
  `~/.cursor/skills/`; project-local alternatives may use `.agents/skills/` or
  `.cursor/skills/`.
- Use Cursor todos and subagents when exposed.
- Continue the active agent run while state is `running`; a todo update alone
  is not a reason to pause.
- Invoke the installed worklog skill or its documented helper commands for
  durable context. If unavailable, use one durable project tracker and label the
  fallback.
- Use a configured Cursor automation or hook only after verifying it exists and
  has a bounded stop rule. Each recurrence wakes the agent to resume a bound
  successor. Otherwise end `needs_human`.

## OpenCode

- Discover skills from the repo's `skills/` directory (see the Opencode resolver
  in `SKILL.md`) or the project's configured skill root.
- Delegate through the `task` tool (with a chosen `subagent_type`) and an
  explicit child-slug description;
  workers are read-only unless a private worktree is proven (see
  `references/crew.md`).
- Continue the active run while state is `running`; there is no mailbox wait —
  begin the next cycle immediately.
- Invoke the installed worklog skill via `$WORKLOG_BIN` host-agnostic paths for
  durable context; label the fallback if unavailable.
- No verified recurrence primitive is assumed; for scheduled continuation, end
  `needs_human` unless one is discovered and verified.

## Compatibility rule

Never encode a host-only hook, command substitution, tool name, or permission
grant in the portable root skill. Keep host differences in this reference and
degrade explicitly when a capability is absent.
