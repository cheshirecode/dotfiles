# Mode: `spawn`

Emit a self-contained handoff prompt for the selected host. The receiving session assumes **no memory** of the current conversation — the prompt must stand alone. This mode generates text; it does not launch an agent.

**Does not run the preamble.** No LDAP resolution, no `_worklog` pull, no repo writes. Pure prompt generator.

**Env prerequisite (no-preamble mode):** helpers still need a shell with `WORKLOG_BIN` / `WORKLOG_REPO` (and usually `WORKLOG_LDAP`) set. Prefer `direnv exec "$WORKLOG_REPO" …`. Bake the exports into the handoff prompt below so the cold session does not invent empty env.

## Steps

1. Parse the free-form task from the argument verbatim. Everything after `spawn` is the task description.
2. Resolve `$PROJECTS_DIR` using the same rules as the preamble: `dirname "$(git rev-parse --show-toplevel)"` → first existing of `~/Documents/projects` `~/projects` `~/code` `~/src` `~/dev` `~/repos` → ask. Do not clone or pull.
3. Infer which repos and skill files the task touches (keyword match on the description — e.g. `cheshirecode/<repo>` / `cheshirecode/<repo>` / `cheshirecode/<repo>`, or skill names from `.claude/skills/`). Include only what's relevant; don't dump everything.
4. Render the handoff prompt inside a fenced code block. Do **not** execute it.

## Prompt template

```
You're picking up a task cold. Assume no prior session memory.

Project root: <$PROJECTS_DIR>
Relevant repos:
  - <$PROJECTS_DIR>/<repo-a>
  - <$PROJECTS_DIR>/<repo-b>

Worklog env (required before any $WORKLOG_BIN helper):
  export WORKLOG_BIN="<verified-skill-bin-on-receiving-host>"
  export WORKLOG_REPO="${WORKLOG_REPO:-<$PROJECTS_DIR>/_worklog}"
  export WORKLOG_LDAP=<ldap-for-this-task>   # e.g. fredtran — omit --ldap on search sweeps to see all namespaces
  # Prefer: direnv exec "$WORKLOG_REPO" env WORKLOG_LDAP=<ldap> "$WORKLOG_BIN/<helper>.sh" …

Read these first (in order):
  - $WORKLOG_REPO/AGENTS.md          # worklog protocol
  - <$PROJECTS_DIR>/<repo>/AGENTS.md            # repo conventions (if the task touches code)
  - <path to any skill SKILL.md that governs the work>
  - <path to the active worklog task file, if one exists>

Task:
  <verbatim task description from the user>

Contract:
  <task/attempt ID, accepting owner, repo remote and expected revision/diff>
  <accepted shared decisions and constraints, source revision; unresolved questions>
  <owned write scope, existing branch/worktree, acceptance checks, remaining budget/unit>

Deliverables:
  <one-line expectation — PR, file, prompt, report, etc.>
  <agreed return format: task/source identity, status, evidence, uncertainty, next action>
  <checkpoint owner: parent for shared delegates; receiving session for an authorized takeover>
```

Tune the "Read these first" list to the task. Examples:
- Task touches `_worklog` protocol → include `_worklog/AGENTS.md` + `_worklog/docs/protocol.md`.
- Task edits a skill → include that skill's `SKILL.md`.
- Task is a code change in a known repo → include that repo's root `AGENTS.md` and the nearest nested `AGENTS.md`.
- Task is pure research / survey → worklog `AGENTS.md` only.

Keep the prompt under ~30 lines. If the task is genuinely large, point at a single design doc in the prompt rather than inlining its content.

Resolve paths on the receiving host and verify source identity before acting;
sender-local temporary paths are not durable evidence. A copied decision is a
dated snapshot; its named source wins. Use [context.md](context.md#reuse-and-prompt-caching)
for stable prefix layout and freshness. Loop delegates use the return contract in
[durable-context.md](../../loop-engineering/references/durable-context.md).
